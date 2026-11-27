import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zed_specials/src/models.dart';

import '../tool/src/history.dart';
import '../tool/src/matching.dart';

Catalogue leaflet(String id, String shop, DateTime from, DateTime to) =>
    Catalogue(
      id: id,
      retailerId: shop,
      title: id,
      sourceUrl: 'https://example.com/$id',
      pages: const [],
      validFrom: from,
      validTo: to,
    );

DealItem item(
  String id,
  String catalogue,
  String shop,
  String name,
  double price, {
  double? qty,
  String? unit,
}) => DealItem(
  id: id,
  catalogueId: catalogue,
  retailerId: shop,
  page: 1,
  name: name,
  price: price,
  sizeQty: qty,
  sizeUnit: unit,
);

void main() {
  final a = leaflet(
    'a',
    'shoprite',
    DateTime(2026, 11, 1),
    DateTime(2026, 11, 14),
  );
  final b = leaflet(
    'b',
    'shoprite',
    DateTime(2026, 11, 15),
    DateTime(2026, 11, 28),
  );
  final c = leaflet(
    'c',
    'picknpay',
    DateTime(2026, 11, 16),
    DateTime(2026, 11, 29),
  );

  DealItem marg(String cat, double price, {String shop = 'shoprite'}) => item(
    '$cat-1',
    cat,
    shop,
    'Buttercup Margarine 500g',
    price,
    qty: 500,
    unit: 'g',
  );

  test('a first sighting has no history', () {
    final h = PriceHistory();
    final out = h.record([a], [marg('a', 35)], DateTime(2026, 11, 2));
    expect(out.single.history, isEmpty);
    expect(h.products, hasLength(1));
  });

  test('the next leaflet shows the earlier price and the drop', () {
    final h = PriceHistory();
    h.record([a], [marg('a', 35)], DateTime(2026, 11, 2));
    final out = h.record([b], [marg('b', 30)], DateTime(2026, 11, 15));

    final history = out.single.history;
    expect(history, hasLength(1));
    expect(history.single.price, 35);
    expect(history.single.from, DateTime(2026, 11, 1));
    expect(history.single.to, DateTime(2026, 11, 14));
    expect(out.single.dropSinceLast, 5);
    expect(h.products, hasLength(1), reason: 'same product, two leaflets');
  });

  test('a leaflet that is still published is not history', () {
    final h = PriceHistory();
    final out = h.record(
      [a, b],
      [marg('a', 35), marg('b', 30)],
      DateTime(2026, 11, 15),
    );
    expect(out.every((i) => i.history.isEmpty), isTrue);
  });

  test('earlier prices at another shop are included', () {
    final h = PriceHistory();
    h.record([a], [marg('a', 35)], DateTime(2026, 11, 2));
    final out = h.record(
      [c],
      [marg('c', 33, shop: 'picknpay')],
      DateTime(2026, 11, 16),
    );
    final history = out.single.history;
    expect(history.single.retailerId, 'shoprite');
    expect(history.single.price, 35);
    // Not this shop's own earlier price, so no "down" badge.
    expect(out.single.dropSinceLast, isNull);
  });

  test('a different pack size is a different product', () {
    final h = PriceHistory();
    h.record([a], [marg('a', 35)], DateTime(2026, 11, 2));
    final out = h.record(
      [b],
      [
        item(
          'b-1',
          'b',
          'shoprite',
          'Buttercup Margarine 1kg',
          62,
          qty: 1000,
          unit: 'g',
        ),
      ],
      DateTime(2026, 11, 15),
    );
    expect(out.single.history, isEmpty);
  });

  test('re-reading a published leaflet replaces its prices', () {
    final h = PriceHistory();
    h.record([a], [marg('a', 3500)], DateTime(2026, 11, 2)); // misread
    h.record([a], [marg('a', 35)], DateTime(2026, 11, 3)); // reader fixed
    expect(h.products, hasLength(1));
    expect(h.products.single.prices.values, [35]);
  });

  test('a wildly different price is not taken for the same product', () {
    final h = PriceHistory();
    h.record([a], [marg('a', 35)], DateTime(2026, 11, 2));
    final out = h.record([b], [marg('b', 3500)], DateTime(2026, 11, 15));
    expect(out.single.history, isEmpty);
  });

  test('the store survives a save and a load', () {
    final dir = Directory.systemTemp.createTempSync('zed_history');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/history.json');

    final h = PriceHistory();
    h.record([a], [marg('a', 35)], DateTime(2026, 11, 2));
    h.save(file);

    final again = PriceHistory.load(file);
    expect(again.firstSeen('a'), DateTime(2026, 11, 2));
    final out = again.record([b], [marg('b', 30)], DateTime(2026, 11, 15));
    expect(out.single.history.single.price, 35);

    // Saving twice in a row writes the same bytes, so a run with nothing
    // new leaves no change to commit.
    again.save(file);
    final first = file.readAsStringSync();
    PriceHistory.load(file).save(file);
    expect(file.readAsStringSync(), first);
  });

  test('a damaged store is an error, not an empty history', () {
    final dir = Directory.systemTemp.createTempSync('zed_history');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/history.json')..writeAsStringSync('{"ver');
    expect(() => PriceHistory.load(file), throwsA(anything));
  });

  test('leaflets that ended long ago are forgotten', () {
    final h = PriceHistory();
    h.record([a], [marg('a', 35)], DateTime(2026, 11, 2));
    final late = leaflet(
      'z',
      'shoprite',
      DateTime(2028, 6, 1),
      DateTime(2028, 6, 14),
    );
    final out = h.record([late], [marg('z', 40)], DateTime(2028, 6, 1));
    expect(out.single.history, isEmpty);
    expect(h.leaflets.keys, [shortId('z')]);
  });

  test('an unsized match needs close prices', () {
    final two = item('1', 'a', 'shoprite', 'Pine Gel Boom Pine Gel 2', 56);
    final one = item(
      '2',
      'c',
      'picknpay',
      'Boom Pine Gel 1Litre',
      34.99,
      qty: 1000,
      unit: 'ml',
    );
    expect(sameProduct(two, one), isFalse);
  });
}
