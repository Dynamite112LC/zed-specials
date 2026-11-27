import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zed_specials/src/models.dart';

import '../tool/src/extract.dart';
import '../tool/src/page_reader.dart';
import '../tool/src/second_reader.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

/// A real page read by both readers. The ".vision.json" files are what the
/// vision model said about these pages in a trial run.
PageReading _twice(String retailer, String page, {bool flashes = true}) =>
    readPage(
      retailer,
      ocr: _load('$page.ocr.json'),
      flashes: flashes ? _load('$page.flashes.json') : null,
      second: _load('$page.vision.json'),
    );

ExtractedItem _item(String name, double price) =>
    ExtractedItem(name: name, price: price, crop: const CropBox(0, 0, 10, 10));

void main() {
  group('names', () {
    test('a size the first reader garbled comes from the second', () {
      expect(
        mergeNames('Zeus Dump Truck 3b', 'Zeus Dump Truck 36cm'),
        'Zeus Dump Truck 36cm',
      );
      expect(
        mergeNames('Boom Pine Gel 2', 'Boom Pine Gel 2L'),
        'Boom Pine Gel 2L',
      );
      expect(
        mergeNames(
          'Sta-soft Fabric Softener Alss AA',
          'Sta-soft Fabric Softener Assorted 2L',
        ),
        'Sta-soft Fabric Softener Assorted 2L',
      );
    });

    test('a size only the second reader saw is added', () {
      expect(
        mergeNames(
          'Sunlight Dishwashing Liquid Lemon',
          'Sunlight Dishwashing Liquid Lemon 750ml',
        ),
        'Sunlight Dishwashing Liquid Lemon 750ml',
      );
      expect(
        mergeNames(
          'Battery-operated Racing Car',
          'Z8 Battery-operated Racing Car',
        ),
        'Z8 Battery-operated Racing Car',
      );
    });

    test('words stay as the first reader spelled them', () {
      expect(
        mergeNames(
          'Shoprite Friction Truck 12cm',
          'Shoprite Frition Truck 12cm',
        ),
        'Shoprite Friction Truck 12cm',
      );
      expect(
        mergeNames(
          'Dettol Bath Soap Assorted 175g',
          'Detoil Bath Soap Assorted 175g',
        ),
        'Dettol Bath Soap Assorted 175g',
      );
      // Not a size: the first reader's number stands.
      expect(
        mergeNames(
          'Huggies Nappies 42/44/46/52/58',
          'Huggies Nappies 42/44/46/52/56',
        ),
        'Huggies Nappies 42/44/46/52/58',
      );
    });

    test('plain words only the second reader gives are left out', () {
      expect(
        mergeNames(
          'Whitespoon Household White Sugar 2kg',
          'Household Sugar Whitespoon Household White Sugar 2kg',
        ),
        'Whitespoon Household White Sugar 2kg',
      );
      // And the first reader's own extra words are kept.
      expect(
        mergeNames('Simple choice 20L PVA Paint', '20L PVA Paint'),
        'Simple choice 20L PVA Paint',
      );
    });

    test('names with nothing in common are left alone', () {
      expect(
        mergeNames('Pork Leg Roast', 'Chicken Braai Pack 2kg'),
        'Pork Leg Roast',
      );
    });
  });

  group('prices', () {
    test('the same price from both readers is agreed', () {
      final r = combineReadings(
        [_item('Boom Washing Powder 1kg', 55)],
        [const SecondItem('Boom Washing Powder 1kg', 55)],
      );
      expect(r.items.single.agreed, isTrue);
      expect(r.items.single.otherPrice, isNull);
      expect(r.agreed, 1);
    });

    test('other kwacha: the first stands and the second is carried', () {
      final r = combineReadings(
        [_item('Freehand Colour Base Stemless Glass', 24.99)],
        [const SecondItem('Freehand Colour Base Stemless Glass', 19.99)],
      );
      expect(r.items.single.price, 24.99);
      expect(r.items.single.agreed, isFalse);
      expect(r.items.single.otherPrice, 19.99);
      expect(r.doubted, 1);
      expect(r.notes.single, contains('to be checked'));
    });

    test('ngwee only the second reader saw are believed, and flagged', () {
      // The first reader missed the raised 99.
      final r = combineReadings(
        [_item('Bestmade Plush Bear 1m', 399)],
        [const SecondItem('Bestmade Plush Bear 1m', 399.99)],
      );
      expect(r.items.single.price, 399.99);
      expect(r.items.single.otherPrice, 399);
      expect(r.items.single.agreed, isFalse);
      // "90" for the raised "99".
      final ninety = combineReadings(
        [_item('Parmalat Cheese Slices 200g', 53.90)],
        [const SecondItem('Parmalat Cheese Slices 200g', 53.99)],
      );
      expect(ninety.items.single.price, 53.99);
      expect(ninety.items.single.otherPrice, 53.90);
    });

    test('ngwee the second reader left out say nothing', () {
      final r = combineReadings(
        [_item('Softex 2-ply Toilet Rolls 10', 67.99)],
        [const SecondItem('Softex 2-ply Toilet Rolls 10', 67)],
      );
      expect(r.items.single.price, 67.99);
      expect(r.items.single.otherPrice, isNull);
      expect(r.items.single.agreed, isFalse);
      expect(r.doubted, 0);
    });

    test('a dropped decimal point is not a disagreement, nor agreement', () {
      final r = combineReadings(
        [_item('Fruitop Fruit Juice Blend 1.5L', 26.99)],
        [const SecondItem('Fruitop Fruit Juice Blend 1.5L', 2699)],
      );
      expect(r.items.single.price, 26.99);
      expect(r.items.single.otherPrice, isNull);
      expect(r.items.single.agreed, isFalse);
    });

    test('two items at one price are told apart by their names', () {
      final r = combineReadings(
        [
          _item('Boom Dishwashing Liquid 750ml', 30),
          _item('Domestos Thick Bleach 750', 30),
        ],
        [
          const SecondItem('Domestos Thick Bleach 750ml', 30),
          const SecondItem('Boom Dishwashing Liquid 750ml', 30),
        ],
      );
      expect(r.items[0].name, 'Boom Dishwashing Liquid 750ml');
      expect(r.items[1].name, 'Domestos Thick Bleach 750ml');
      expect(r.items[1].firstName, 'Domestos Thick Bleach 750');
    });

    test('an item only the second reader names needs the page to back it', () {
      final r = combineReadings(
        [_item('Pork Leg Roast', 13.49)],
        [const SecondItem('Golden Unicorn Statue', 4999)],
      );
      expect(r.items, hasLength(1));
      expect(r.added, 0);
      expect(r.notes.single, contains('left out'));
    });

    test('a multi-buy agrees when the second reader gives the deal', () {
      final r = combineReadings(
        [_item('Amigo Crisps Assorted (2 for K50)', 25)],
        [const SecondItem('Amigo Crisps 2x110g', 50)],
      );
      expect(r.items.single.agreed, isTrue);
      expect(r.items.single.price, 25);
      // The deal stays in the name; "2x110g" is not this item's pack size.
      expect(r.items.single.name, 'Amigo Crisps Assorted (2 for K50)');
      expect(r.items.single.sizeQty, isNull);
    });

    test('assumed ngwee give way on a page priced in whole kwacha', () {
      ExtractedItem rice() => ExtractedItem(
        name: 'White Rice 5kg',
        price: 99.99,
        crop: const CropBox(0, 0, 10, 10),
        assumedNgwee: true,
      );
      final cover = combineReadings(
        [
          rice(),
          _item('Blue Band Margarine 1kg', 65),
          _item('Africa Milling Maize Meal 10kg', 69),
          _item('Lacto Milk Drink 250ml', 5),
        ],
        const [
          SecondItem('Parboiled White Rice', 99),
          SecondItem('Blue Band Margarine', 65),
          SecondItem('Africa Milling Breakfast Meal', 69),
          SecondItem('Lacto Milk Drink', 5),
        ],
      );
      expect(cover.items.first.price, 99);
      expect(cover.items.first.agreed, isTrue);
      expect(cover.items.first.otherPrice, isNull);

      // On a page of .99 prices the assumption is the better guess: the
      // second reader has only left the ngwee out.
      final household = combineReadings(
        [
          rice(),
          _item('Softex 2-ply Toilet Rolls 10', 67.99),
          _item('Nugget Black Shoe Polish 100ml', 42.99),
          _item('Doom Insecticide Assorted 300ml', 39.99),
        ],
        const [
          SecondItem('Parboiled White Rice', 99),
          SecondItem('Softex 2-ply Toilet Rolls 10', 67.99),
          SecondItem('Nugget Black Shoe Polish 100ml', 42.99),
          SecondItem('Doom Insecticide Assorted 300ml', 39.99),
        ],
      );
      expect(household.items.first.price, 99.99);
      expect(household.items.first.otherPrice, isNull);
    });

    test('lone ngwee on a whole-kwacha page are doubted, not believed', () {
      final r = combineReadings(
        [
          _item('Boom Washing Powder 1kg', 55),
          _item('Rapid Washing Powder Bucket 1.5kg', 79),
          _item('Air Scents Air Freshener 200ml', 25),
          _item('Mortein Insecticide 300ml', 32),
          _item('Kiwi Shoe Polish 100ml', 40),
          _item('Dawn Body Lotion 400ml', 36),
        ],
        const [
          SecondItem('Boom Washing Powder 1kg', 55.99),
          SecondItem('Rapid Washing Powder Bucket 1.5kg', 79),
          SecondItem('Air Scents Air Freshener 200ml', 25),
          SecondItem('Mortein Insecticide 300ml', 32),
          SecondItem('Kiwi Shoe Polish 100ml', 40),
          SecondItem('Dawn Body Lotion 400ml', 36),
        ],
      );
      expect(r.items.first.price, 55);
      expect(r.items.first.otherPrice, 55.99);
    });

    test('a dropped point with other ngwee is read as that price', () {
      // The first reader took the raised 99 for 00; the second ran it in.
      final r = combineReadings(
        [_item('Buttercup Margarine Brick 250g', 17)],
        [const SecondItem('Buttercup Margarine Brick 250g', 1799)],
      );
      expect(r.items.single.price, 17.99);
      expect(r.items.single.otherPrice, 17);
    });

    test('a dropped point with a digit lost is not a second opinion', () {
      final r = combineReadings(
        [_item("Jacob's Instant Coffee 200g", 269.99)],
        [const SecondItem("Jacob's Instant Coffee 200g", 2699)],
      );
      expect(r.items.single.otherPrice, isNull);
      expect(r.items.single.agreed, isFalse);
    });

    test('a combo listed piece by piece adds nothing', () {
      final page = OcrPage(1000, 1000, [
        OcrLine('299', 400, 400, 120, 60, 60, 1),
        OcrLine('OLI REFINED PURE VEGETABLE OIL', 380, 470, 200, 20, 20, 1),
        OcrLine('HARVEST MARGARINE', 380, 495, 200, 20, 20, 1),
      ]);
      final r = combineReadings(
        [
          _item('Pork Leg Roast', 13),
          _item('Variety Braai Pack', 19),
          _item('Beef Mince', 85),
        ],
        [
          const SecondItem('Oli Refined Pure Vegetable Oil 2.5L', 299),
          const SecondItem('Harvest Margarine 500g', 299),
        ],
        page: page,
      );
      expect(r.added, 0);
      expect(r.items, hasLength(3));
      // One product at that price, with its words beside it, is added.
      final single = combineReadings(
        [
          _item('Pork Leg Roast', 13),
          _item('Variety Braai Pack', 19),
          _item('Beef Mince', 85),
        ],
        [const SecondItem('Oli Refined Pure Vegetable Oil 2.5L', 299)],
        page: page,
      );
      expect(single.added, 1);
      expect(single.items.last.price, 299);
    });

    test('words and sizes run together are pulled apart', () {
      expect(
        mergeNames('All Gold Tomato SAUUEOml', 'All Gold Tomato Sauce 700ml'),
        'All Gold Tomato Sauce 700ml',
      );
      expect(
        mergeNames('Queen Tomato Paste 32oeach', 'Queen Tomato Paste 320g'),
        'Queen Tomato Paste 320g',
      );
      // A real word is not mistaken for a garbled size.
      expect(
        mergeNames(
          "Farmer's Choice IQF Mixed Chicken Portions",
          "Farmer's Choice 1kg Mixed Portions Chicken",
        ),
        "Farmer's Choice IQF 1kg Mixed Chicken Portions",
      );
      expect(
        mergeNames('Pure Cooking Oil 2 Litre', 'Pure Cooking Oil 2L'),
        'Pure Cooking Oil 2 Litre',
      );
    });

    test('a failed attempt is not a reading', () {
      expect(parseSecondReading({'failed': 1, 'error': 'timed out'}), isNull);
      expect(parseSecondReading(null), isNull);
      expect(
        parseSecondReading({
          'items': [
            {'name': 'BOOM PINE GEL 2L EACH', 'price': 56},
            {'name': '???', 'price': 5},
            {'name': 'Free gift', 'price': 0},
            {'name': 'No price'},
          ],
        })!.single.name,
        'Boom Pine Gel 2L',
      );
    });
  });

  group('real pages read twice', () {
    test('toys: the two items the first reader missed are found', () {
      final r = _twice('shoprite', 'shoprite-toys');
      final byName = {for (final i in r.items) i.name: i};
      expect(r.items, hasLength(24));
      expect(r.second!.added, 2);
      expect(byName["Boys / Girls' BMX Bike 30cm"]!.price, 999.99);
      expect(
        byName['Challenger Stunt Radio-controlled Vehicle']!.price,
        499.99,
      );
      // They have a place on the page, for the enlarged view.
      final bmx = byName["Boys / Girls' BMX Bike 30cm"]!;
      final box = bmx.regionOn(r.width, r.height);
      expect(box.x, inInclusiveRange(1000, 1400));
      expect(box.y, inInclusiveRange(350, 700));
      // Sizes repaired, spelling kept.
      expect(byName, contains('Zeus Dump Truck 36cm'));
      expect(byName, contains('Racer Die-cast Car Assorted 9cm'));
      expect(byName, contains('Z8 Battery-operated Racing Car'));
      expect(byName, contains('Shoprite Friction Truck 12cm'));
      expect(r.items.where((i) => i.agreed), hasLength(24));
      expect(r.second!.doubted, 0);
    });

    test('food: lost litres come back, and with them the pack size', () {
      final r = _twice('shoprite', 'shoprite-food');
      final byName = {for (final i in r.items) i.name: i};
      expect(r.items, hasLength(33));
      expect(byName['Boom Pine Gel 2L']!.sizeQty, 2000);
      expect(byName['Boom Pine Gel 2L']!.sizeUnit, 'ml');
      expect(byName['Sta-soft Fabric Softener Assorted 2L']!.sizeQty, 2000);
      expect(byName, contains('Xssentials Mini Oven 24L'));
      expect(byName, contains('Dettol Bath Soap Assorted 175g'));
      // The one the second reader missed is still there, just not agreed.
      final kiwi = byName['Kiwi Shoe Polish Assorted 100ml']!;
      expect(kiwi.price, 40);
      expect(kiwi.agreed, isFalse);
      expect(r.second!.agreed, 32);
      expect(r.second!.doubted, 0);
    });

    test(
      'game: the second reader\'s dropped decimal points change nothing',
      () {
        final r = _twice('game', 'game-appliances', flashes: false);
        final byName = {for (final i in r.items) i.name: i};
        expect(r.items, hasLength(17));
        expect(byName['Fruitop Fruit Juice Blend 1.5L Assorted']!.price, 26.99);
        expect(byName['Soyola Pure Refine Oil 5L']!.price, 209.99);
        expect(byName['Samsung Galaxy A07 64GB 4G Smartphone']!.agreed, isTrue);
        expect(r.second!.agreed, 12);
        expect(r.second!.doubted, 0);
        expect(r.second!.added, 0);
      },
    );

    test('nothing is added on a page with no text to back it', () {
      final r = readPage(
        'picknpay',
        ocr: {'width': 100, 'height': 100, 'lines': <dynamic>[]},
        second: {
          'items': [
            {'name': 'Something Else Entirely', 'price': 10},
          ],
        },
      );
      expect(r.items, isEmpty);
    });
  });

  group('in the feed', () {
    DealItem item({bool agreed = false, double? other, String? first}) =>
        DealItem(
          id: 'a',
          catalogueId: 'c',
          retailerId: 'shoprite',
          page: 1,
          name: 'Boom Pine Gel 2L',
          price: 56,
          agreed: agreed,
          otherPrice: other,
          firstName: first,
        );

    test('the two-reader marks survive the feed', () {
      final back = DealItem.fromJson(
        jsonDecode(
              jsonEncode(item(other: 65, first: 'Boom Pine Gel 2').toJson()),
            )
            as Map<String, dynamic>,
      );
      expect(back.otherPrice, 65);
      expect(back.inDoubt, isTrue);
      expect(back.firstName, 'Boom Pine Gel 2');
      expect(item(agreed: true).toJson()['agreed'], isTrue);
      expect(item().toJson().containsKey('agreed'), isFalse);
    });

    test('a correction settles a doubt', () {
      final fixed = item(other: 65).copyWith(price: 65, corrected: true);
      expect(fixed.inDoubt, isFalse);
    });

    test('a correction against either reading applies', () {
      // Made when K399 was shown; the second reading has since put K399.99
      // in its place and carries the K399.
      final fix = Correction(
        leaflet: 'c',
        page: 1,
        readName: 'Boom Pine Gel 2L',
        readPrice: 399,
        price: 389.99,
      );
      final now = item(other: 399).copyWith(price: 399.99);
      final out = applyCorrections([now], [fix]);
      expect(out.single.price, 389.99);
      expect(out.single.inDoubt, isFalse);
    });

    test('a correction made before the name was repaired still applies', () {
      final fix = Correction(
        leaflet: 'c',
        page: 1,
        readName: 'Boom Pine Gel 2',
        readPrice: 56,
        price: 65,
      );
      final out = applyCorrections([item(first: 'Boom Pine Gel 2')], [fix]);
      expect(out.single.price, 65);
      expect(out.single.corrected, isTrue);
    });
  });
}
