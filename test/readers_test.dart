// Checks the leaflet readers against real pages (OCR output saved in
// test/fixtures), so a change to one layout's rules cannot quietly break
// another's. The expected prices were checked against the page images.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/extract.dart';

List<ExtractedItem> read(String shop, String fixture) {
  Map<String, dynamic> load(String name) =>
      jsonDecode(File('test/fixtures/$name').readAsStringSync())
          as Map<String, dynamic>;
  final flashes = File('test/fixtures/$fixture.flashes.json');
  return extractItems(
    shop,
    OcrPage.fromJson(
      load('$fixture.ocr.json'),
      flashes: flashes.existsSync() ? load('$fixture.flashes.json') : null,
    ),
  );
}

/// The price of the one item whose name contains every one of [words].
double priceOf(List<ExtractedItem> items, String words) {
  final wanted = words.toLowerCase().split(' ');
  final hits = items.where((i) {
    final name = i.name.toLowerCase();
    return wanted.every(name.contains);
  }).toList();
  expect(hits, hasLength(1), reason: 'items named "$words"');
  return hits.single.price;
}

void main() {
  group('Shoprite toys page: descriptions beside or above the price', () {
    final items = read('shoprite', 'shoprite-toys');

    test('reads every yellow flash with its ngwee', () {
      const expected = {
        'zeus mini bike': 299.99,
        'zeus harley': 499.99,
        'zeus quad bike': 699.99,
        'super racing car': 14.99,
        'racer die-cast': 19.99,
        'shoprite friction truck': 29.99,
        'racing friction car assorted 10cm': 39.99,
        'king racing': 59.99,
        'robots transforming': 99.99,
        'super convoy': 149.99,
        'plastic construction truck': 59.99,
        'robots deformation': 129.99,
        'tools building': 69.99,
        'zeus mini dump truck': 149.99,
        'zeus dump truck 3': 199.99,
        'future police': 99.99,
        'engineering series': 49.99,
        'ultra die-cast': 99.99,
        'race high speed': 69.99,
        'rock crawler': 299.99,
      };
      expected.forEach((words, price) {
        expect(priceOf(items, words), price, reason: words);
      });
    });

    test('reads the starburst prices too', () {
      expect(priceOf(items, 'superior radio-controlled'), 699.99);
    });

    test('keeps a description with its own price', () {
      // The robots sit right under the K14.99 racing car; they are K99.99.
      expect(priceOf(items, 'robots transforming'), isNot(14.99));
    });
  });

  group('Shoprite food page: descriptions under the price', () {
    final items = read('shoprite', 'shoprite-food');

    test('reads all 33 products', () {
      expect(items, hasLength(33));
    });

    test('whole-kwacha prices', () {
      const expected = {
        'dettol bath soap': 13.0,
        'colgate': 22.0,
        'foam bath': 80.0,
        'sanitary pads': 5.0,
        'roll-on': 28.0,
        'body spritzer': 26.0,
        'hoity toity': 44.0,
        'rexona shield deodorant': 46.0,
        'vaseline': 19.0,
        'banja': 15.0,
        'rapid washing powder': 79.0,
        'boom dishwashing': 30.0,
        'domestos': 30.0,
        'kiwi shoe polish': 40.0,
        'pine gel': 56.0,
        'shield sheen': 60.0,
        'shield splash': 220.0,
        'mini oven': 2200.0,
        'cooler box': 300.0,
      };
      expected.forEach((words, price) {
        expect(priceOf(items, words), price, reason: words);
      });
    });

    test('starburst prices at the top of the page', () {
      expect(priceOf(items, 'boom washing powder 4.5kg'), 178.0);
      expect(priceOf(items, 'huggies'), 175.0);
      expect(priceOf(items, 'sta-soft'), 56.0);
      expect(priceOf(items, 'baby soft'), 185.0);
    });

    test('neighbouring descriptions do not run together', () {
      final rexona = items.firstWhere(
        (i) => i.name.contains('Rexona Shield Deodorant'),
      );
      expect(rexona.name, isNot(contains('Vaseline')));
    });
  });

  group('Shoprite butchery page: yellow prices on red', () {
    final items = read('shoprite', 'shoprite-butchery');

    test('per-kilogram prices with ngwee', () {
      final mince = items.firstWhere((i) => i.name.contains('Beef Mince'));
      expect(mince.price, 102.99);
      expect(mince.perKg, isTrue);
      expect(priceOf(items, 'thick boerewors'), 149.99);
      expect(priceOf(items, 'braai pack'), 159.99);
    });

    test('a starburst price that lost a raised digit', () {
      // Printed K134.99; OCR sees "K1349".
      expect(priceOf(items, 'forequarter'), 134.99);
    });

    test('deli and bakery prices', () {
      expect(priceOf(items, 'back bacon'), 59.99);
      expect(priceOf(items, 'vetkoek'), 14.99);
      expect(priceOf(items, 'chip roll'), 9.99);
      expect(priceOf(items, 'seedless grapes'), 99.99);
    });
  });

  group('Game appliances page: description above or below the price', () {
    final items = read('game', 'game-appliances');

    test('reads all 17 products', () {
      expect(items, hasLength(17));
    });

    test('groceries, with the description left of the price', () {
      expect(priceOf(items, 'fruitop'), 26.99);
      expect(priceOf(items, 'whitespoon'), 62.99);
      expect(priceOf(items, 'surf'), 189.99);
    });

    test('appliances keep their brand and lose the feature list', () {
      expect(priceOf(items, 'philips dry iron'), 419.0);
      expect(priceOf(items, 'adventure 200 camping chair'), 290.0);
      expect(priceOf(items, 'trojan pursuit 400 stationary bike'), 4490.0);
      expect(priceOf(items, 'hisense titan inox'), 6999.0);
      for (final i in items) {
        expect(i.name, isNot(contains('Item no')), reason: i.name);
        expect(i.name, isNot(contains('Maximum weight')), reason: i.name);
      }
    });
  });
}
