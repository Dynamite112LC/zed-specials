import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zed_specials/src/models.dart';

import 'package:zed_specials/src/widgets.dart';

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

  group('Smart Shopper deals for several', () {
    // "6.99 Each", then in the Smart Shopper box "50.00 FOR 10".
    List<OcrLine> doughnuts({required bool asOneLine}) => [
      _line('6', 907, 1293, 44, 59),
      _line('99', 946, 1295, 49, 35),
      _line('Each', 956, 1328, 21, 8),
      _line('PnP Custard', 911, 1347, 86, 17),
      _line('Doughnuts', 915, 1361, 78, 17),
      _line('50', 895, 1395, 81, 54),
      _line('00', 966, 1397, 49, 32),
      if (asOneLine)
        // As OCR reads it.
        _line('FOR 10', 972, 1423, 39, 19)
      else ...[
        // As a PDF's text has it: two runs in different sizes.
        _line('10', 988, 1426, 18, 14),
        _line('FOR', 974, 1430, 18, 8),
      ],
    ];
    List<OcrLine> smallPrint() => [
      for (var i = 0; i < 4; i++)
        _line(
          'Promotion valid while stocks last at all stores',
          100,
          2300.0 + 22 * i,
          500,
          17,
        ),
    ];

    for (final asOneLine in [true, false]) {
      test('"50.00 FOR 10" is K5 each for ten '
          '(${asOneLine ? 'one line' : 'two runs'})', () {
        final item = extractItems(
          'picknpay',
          OcrPage(1753, 2479, [
            ...doughnuts(asOneLine: asOneLine),
            ...smallPrint(),
          ]),
        ).single;
        expect(item.name, 'PNP Custard Doughnuts');
        expect(item.price, 6.99);
        expect(item.cardPrice, 5);
        expect(item.cardQty, 10);
      });
    }

    test('a price for one has no quantity', () {
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
        ..._smallPrint(),
      ]);
      final chicken = extractItems('picknpay', page).single;
      expect(chicken.cardPrice, 109.99);
      expect(chicken.cardQty, isNull);
    });

    const doughnut = DealItem(
      id: 'a',
      catalogueId: 'c',
      retailerId: 'picknpay',
      page: 2,
      name: 'PnP Custard Doughnuts',
      price: 6.99,
      cardPrice: 5,
      cardQty: 10,
    );
    const water = DealItem(
      id: 'b',
      catalogueId: 'c',
      retailerId: 'picknpay',
      page: 3,
      name: 'Aqua Smooth Purified Water 500ml',
      price: 3.49,
      sizeQty: 500,
      sizeUnit: 'ml',
      // 37.99 for 12.
      cardPrice: 3.1658,
      cardQty: 12,
    );

    test('the deal is worded as the leaflet prints it', () {
      expect(doughnut.cardDeal, '10 for K50');
      expect(water.cardDeal, '12 for K37.99');
      expect(cardNote(doughnut, short: true), '10 for K50 with card');
      expect(
        cardNote(doughnut),
        '10 for K50 with a Smart Shopper card (K5 each)',
      );
      expect(
        cardNote(water),
        '12 for K37.99 with a Smart Shopper card (K3.17 each)',
      );
    });

    test('a card holder sees the price of one in the deal', () {
      final mine = doughnut.withCard();
      expect(mine.price, 5);
      expect(mine.shelfPrice, 6.99);
      expect(mine.cardDeal, '10 for K50');
      expect(cardNote(mine, short: true), 'Card: 10 for K50');
      expect(
        cardNote(mine),
        'Smart Shopper price when you buy 10 for K50. '
        'K6.99 each without the card',
      );
      // Litres are compared at the deal's price too.
      expect(water.withCard().unitPrice, closeTo(6.3316, 0.001));
    });

    test('survives the feed', () {
      final back = DealItem.fromJson(
        jsonDecode(jsonEncode(water.toJson())) as Map<String, dynamic>,
      );
      expect(back.cardQty, 12);
      expect(back.cardDeal, '12 for K37.99');
      expect(back.copyWith(groupId: 'g').cardQty, 12);
    });

    test('the second reader giving the deal total is not a disagreement', () {
      final item = extractItems(
        'picknpay',
        OcrPage(1753, 2479, [...doughnuts(asOneLine: true), ...smallPrint()]),
      ).single;
      final r = combineReadings(
        [item],
        [const SecondItem('PnP Custard Doughnuts', 50)],
      );
      expect(r.items.single.price, 6.99);
      expect(r.items.single.otherPrice, isNull);
      expect(r.items.single.cardQty, 10);
    });
  });

  group('prices per 100g', () {
    final page = OcrPage(1753, 2479, [
      ..._product(
        557,
        918,
        '14',
        '49',
        'PnP Chicken',
        'Biryani',
        card: ('13', '99'),
        each: 'Per 100g',
      ),
      ..._product(253, 918, '59', '99', 'Whitespoon Household', 'Sugar 2kg'),
      ..._smallPrint(),
    ]);
    final items = extractItems('picknpay', page);
    final byName = {for (final i in items) i.name: i};

    test('"Per 100g" beside a Pick n Pay price marks it', () {
      final biryani = byName['PNP Chicken Biryani']!;
      expect(biryani.per100g, isTrue);
      expect(biryani.perKg, isFalse);
      expect(biryani.price, 14.49);
      // The card price under it is per 100g too.
      expect(biryani.cardPrice, 13.99);
      expect(byName['Whitespoon Household Sugar 2kg']!.per100g, isFalse);
    });

    test('the words are not left in the name', () {
      expect(
        cleanName('QUARTER CHICKEN & CHIPS COMBO MEAL per 100g'),
        'Quarter Chicken & Chips Combo Meal',
      );
      expect(saysPer100g('MEAL per 100g'), isTrue);
      expect(saysPer100g('Per100g'), isTrue);
      expect(saysPer100g('Oats 100g'), isFalse);
    });

    test('compares per kilogram with everything else', () {
      const biryani = DealItem(
        id: 'a',
        catalogueId: 'c',
        retailerId: 'picknpay',
        page: 2,
        name: 'PnP Chicken Biryani',
        price: 14.49,
        per100g: true,
        cardPrice: 13.99,
      );
      expect(biryani.priceUnit, '100g');
      expect(biryani.unitPrice, closeTo(144.9, 0.001));
      expect(biryani.unitPriceLabel, 'per kg');
      expect(biryani.withCard().unitPrice, closeTo(139.9, 0.001));
      expect(biryani.withCard().per100g, isTrue);
      final back = DealItem.fromJson(
        jsonDecode(jsonEncode(biryani.toJson())) as Map<String, dynamic>,
      );
      expect(back.per100g, isTrue);
      expect(back.copyWith(price: 15).per100g, isTrue);
      // A per-kilogram price says so, and a pack price says nothing.
      const roast = DealItem(
        id: 'b',
        catalogueId: 'c',
        retailerId: 'shoprite',
        page: 4,
        name: 'Beef Roast',
        price: 192.99,
        perKg: true,
      );
      expect(roast.priceUnit, 'kg');
      expect(roast.toJson().containsKey('per100g'), isFalse);
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
