import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zed_specials/src/scrape/scrapers.dart';

import '../tool/src/scrape_memory.dart';

ScrapedCatalogue cat(String id, String shop, {DateTime? to}) =>
    ScrapedCatalogue(
      id: id,
      retailerId: shop,
      title: id,
      sourceUrl: 'https://example.com/$id',
      validFrom: DateTime(2026, 11, 23),
      validTo: to ?? DateTime(2026, 12, 6),
      ocrImageUrls: ['https://example.com/$id/p1.jpg'],
    );

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zed_memory');
    file = File('${dir.path}/last-scrape.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ScrapeResult> allGood() async => (
    catalogues: [
      cat('s1', 'shoprite'),
      cat('s-short', 'shoprite', to: DateTime(2026, 11, 29)),
      cat('p1', 'picknpay'),
    ],
    errors: <String, String>{},
  );
  Future<ScrapeResult> shopriteRefuses() async =>
      (catalogues: [cat('p2', 'picknpay')], errors: {'shoprite': 'HTTP 403'});

  test(
    'a shop that refuses today is filled in from the last good run',
    () async {
      await scrapeWithMemory(file, allGood, now: DateTime(2026, 11, 27, 6));
      final r = await scrapeWithMemory(
        file,
        shopriteRefuses,
        now: DateTime(2026, 11, 28, 6),
      );
      expect(r.errors, isEmpty);
      expect(
        r.catalogues.map((c) => c.id),
        unorderedEquals(['p2', 's1', 's-short']),
      );
      expect(r.standIns, {'shoprite': DateTime(2026, 11, 27)});
      final s1 = r.catalogues.firstWhere((c) => c.id == 's1');
      expect(s1.validTo, DateTime(2026, 12, 6));
      expect(s1.ocrImageUrls, ['https://example.com/s1/p1.jpg']);
    },
  );

  test('a leaflet stands in until the day it ends, then drops out', () async {
    await scrapeWithMemory(file, allGood, now: DateTime(2026, 11, 27, 6));

    final lastDay = await scrapeWithMemory(
      file,
      shopriteRefuses,
      now: DateTime(2026, 11, 29, 6),
    );
    expect(lastDay.catalogues.map((c) => c.id), contains('s-short'));

    final after = await scrapeWithMemory(
      file,
      shopriteRefuses,
      now: DateTime(2026, 12, 4, 6),
    );
    expect(after.catalogues.map((c) => c.id), unorderedEquals(['p2', 's1']));
    // Still the day the shop itself was last reached, however many runs
    // have stood in since.
    expect(after.standIns, {'shoprite': DateTime(2026, 11, 27)});
  });

  test(
    'when every remembered leaflet has ended the shop is simply absent',
    () async {
      await scrapeWithMemory(file, allGood, now: DateTime(2026, 11, 27, 6));
      final r = await scrapeWithMemory(
        file,
        shopriteRefuses,
        now: DateTime(2026, 12, 20, 6),
      );
      expect(r.errors, isEmpty);
      expect(r.catalogues.map((c) => c.id), ['p2']);
      expect(r.standIns.keys, ['shoprite']);
    },
  );

  test('reaching the shop again ends the stand-in', () async {
    await scrapeWithMemory(file, allGood, now: DateTime(2026, 11, 27, 6));
    await scrapeWithMemory(
      file,
      shopriteRefuses,
      now: DateTime(2026, 11, 28, 6),
    );
    final r = await scrapeWithMemory(
      file,
      allGood,
      now: DateTime(2026, 11, 29, 6),
    );
    expect(r.standIns, isEmpty);
    expect(r.errors, isEmpty);
  });

  test('with nothing remembered the failure stands', () async {
    final r = await scrapeWithMemory(file, shopriteRefuses);
    expect(r.errors.keys, ['shoprite']);
    expect(r.standIns, isEmpty);
  });

  test('days are counted on the calendar', () {
    expect(
      daysBetween(DateTime(2026, 11, 27, 23), DateTime(2026, 11, 28, 1)),
      1,
    );
    expect(daysBetween(DateTime(2026, 11, 27), DateTime(2026, 11, 27, 22)), 0);
  });
}
