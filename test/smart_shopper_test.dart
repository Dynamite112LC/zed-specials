import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zed_specials/src/models.dart';

import '../tool/src/extract.dart';
import '../tool/src/second_reader.dart';

OcrLine _line(String t, double x, double y, double w, double h) =>
    OcrLine(t, x, y, w, h, h, 1);

/// One Pick n Pay product as its text sits on the page: the price, "Each",
/// two lines of description and, for [card], the Smart Shopper price in
/// the box underneath. Sizes are those of a real page.
List<OcrLine> _product(
  double x,
  double y,
  String kwacha,
  String ngwee,
  String line1,
  String line2, {
  (String, String)? card,
  String each = 'Each',
}) => [
  _line(kwacha, x, y, 130, 71),
  _line(ngwee, x + 114, y + 1, 59, 42),
  _line(each, x + 131, y + 43, 28, 12),
  _line(line1, x + 20, y + 67, 140, 20),
  _line(line2, x + 12, y + 85, 158, 20),
  if (card != null) ...[
    _line(card.$1, x - 1, y + 128, 141, 71),
    _line(card.$2, x + 121, y + 130, 59, 42),
    _line(each, x + 130, y + 172, 25, 12),
  ],
];

/// Body text for the reader to size things against, as a real page has.
List<OcrLine> _smallPrint() => [
  for (var i = 0; i < 4; i++)
    _line(
      'Promotion valid while stocks last at all stores',
      100,
      2300.0 + 26 * i,
      600,
      20,
    ),
];

void main() {
  group('Pick n Pay Smart Shopper prices', () {
    final page = OcrPage(1753, 2479, [
      ..._product(
        253,
        669,
        '114',
        '99',
        'PnP IQF Chicken',
        'Mixed Portions 2kg',
        card: ('109', '99'),
      ),
      ..._product(
        687,
        669,
        '99',
        '99',
        'First Choice Butter',
        'Assorted 500g',
        card: ('94', '99'),
      ),
      // No card price for this one.
      ..._product(253, 1100, '59', '99', 'Whitespoon Household', 'Sugar 2kg'),
      // A different, dearer product printed straight underneath is not a
      // card price.
      ..._product(
        687,
        1100,
        '13',
        '99',
        'Coke or Fanta',
        'Cold Drinks 1 Litre',
      ),
      ..._smallPrint(),
    ]);
    final items = extractItems('picknpay', page);
    final byName = {for (final i in items) i.name: i};

    test('the price in the box under the description is the card price', () {
      final chicken = byName['PNP IQF Chicken Mixed Portions 2kg']!;
      expect(chicken.price, 114.99);
      expect(chicken.cardPrice, 109.99);
      expect(byName['First Choice Butter Assorted 500g']!.cardPrice, 94.99);
    });

    test('it is not read as a product of its own', () {
      expect(items, hasLength(4));
    });

    test('a product without the box has no card price', () {
      expect(byName['Whitespoon Household Sugar 2kg']!.cardPrice, isNull);
      expect(byName['Coke or Fanta Cold Drinks 1 Litre']!.cardPrice, isNull);
    });

    test('the item\'s place on the page takes in the card price', () {
      final chicken = byName['PNP IQF Chicken Mixed Portions 2kg']!;
      final box = chicken.regionOn(1753, 2479);
      expect(box.y + box.h, greaterThan(669 + 128 + 60));
    });

    test(
      'a much lower price underneath is another price, not a card price',
      () {
        final odd = OcrPage(1753, 2479, [
          ..._product(
            253,
            669,
            '114',
            '99',
            'PnP IQF Chicken',
            'Mixed Portions 2kg',
            card: ('50', '00'),
          ),
          ..._smallPrint(),
        ]);
        expect(extractItems('picknpay', odd).single.cardPrice, isNull);
      },
    );

    test('the second reader giving the card price is not a disagreement', () {
      final chicken = byName['PNP IQF Chicken Mixed Portions 2kg']!;
      final r = combineReadings(
        [chicken],
        [const SecondItem('PnP IQF Chicken Mixed Portions 2kg', 109.99)],
      );
      expect(r.items.single.price, 114.99);
      expect(r.items.single.otherPrice, isNull);
      expect(r.items.single.cardPrice, 109.99);
    });
  });

  group('the card price in the app', () {
    final chicken = DealItem(
      id: 'a',
      catalogueId: 'c',
      retailerId: 'picknpay',
      page: 1,
      name: 'PnP IQF Chicken Mixed Portions 2kg',
      price: 114.99,
      sizeQty: 2000,
      sizeUnit: 'g',
      cardPrice: 109.99,
      history: [
        PricePoint(
          retailerId: 'picknpay',
          from: DateTime(2026, 11, 1),
          price: 114.99,
        ),
      ],
    );

    test('survives the feed', () {
      final back = DealItem.fromJson(
        jsonDecode(jsonEncode(chicken.toJson())) as Map<String, dynamic>,
      );
      expect(back.cardPrice, 109.99);
      expect(back.cardApplied, isFalse);
    });

    test('a card holder sees and compares the card price', () {
      final mine = chicken.withCard();
      expect(mine.price, 109.99);
      expect(mine.shelfPrice, 114.99);
      expect(mine.cardApplied, isTrue);
      // Per kilogram too.
      expect(mine.unitPrice, closeTo(54.995, 0.001));
      // And back.
      expect(mine.withoutCard().price, 114.99);
      expect(mine.withoutCard().cardApplied, isFalse);
      expect(mine.withCard().price, 109.99);
    });

    test('the card price is not a price drop', () {
      // The last leaflet's price for everyone was the same as today's.
      expect(chicken.dropSinceLast, isNull);
      expect(chicken.withCard().dropSinceLast, isNull);
    });

    test('an item without a card price is left as it is', () {
      const sugar = DealItem(
        id: 'b',
        catalogueId: 'c',
        retailerId: 'picknpay',
        page: 1,
        name: 'Whitespoon Household Sugar 2kg',
        price: 59.99,
      );
      expect(identical(sugar.withCard(), sugar), isTrue);
    });

    test('a correction at or below the card price removes it', () {
      final fixed = chicken.copyWith(price: 104.99, corrected: true);
      expect(fixed.cardPrice, isNull);
      expect(fixed.withCard().price, 104.99);
      final dearer = chicken.copyWith(price: 119.99, corrected: true);
      expect(dearer.cardPrice, 109.99);
    });
  });

  group('per kg on items the second reader adds', () {
    test('small print misread by OCR still counts', () {
      expect(saysPerKg('per kg'), isTrue);
      expect(saysPerKg('ROAST per kg'), isTrue);
      expect(saysPerKg('Pekg'), isTrue);
      expect(saysPerKg('Perkg'), isTrue);
      expect(saysPerKg('1kg BAG'), isFalse);
      expect(saysPerKg('Peking Duck'), isFalse);
    });

    test('"per kg" printed by an added item marks it per kilogram', () {
      final page = OcrPage(
        1530,
        2355,
        [
          _line('PORK LEG', 866, 471, 90, 22),
          _line('ROAST per kg', 864, 494, 130, 22),
          // Another product's small print, far off.
          _line('per kg', 300, 1500, 60, 20),
        ],
        flashes: [
          PriceFlash(
            x: 690,
            y: 450,
            w: 170,
            h: 52,
            th: 52,
            kwacha: '129',
            ngwee: '99',
            ks: 1,
            ns: 1,
            raised: 2,
          ),
        ],
      );
      final r = combineReadings(const [], [
        const SecondItem('Pork Leg Roast', 129.99),
      ], page: page);
      expect(r.added, 1);
      expect(r.items.single.perKg, isTrue);
      expect(r.items.single.name, 'Pork Leg Roast');

      final bun = combineReadings(
        const [],
        [const SecondItem('Pork Leg', 129.99)],
        page: OcrPage(1530, 2355, [
          _line('PORK LEG', 866, 471, 90, 22),
          _line('ROAST EACH', 864, 494, 130, 22),
          _line('per kg', 300, 1500, 60, 20),
        ], flashes: page.flashes),
      );
      expect(bun.items.single.perKg, isFalse);
    });
  });
}
