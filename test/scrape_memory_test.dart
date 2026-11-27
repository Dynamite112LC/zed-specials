import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zed_specials/src/scrape/scrapers.dart';

import '../tool/src/scrape_memory.dart';

ScrapedCatalogue cat(String id, String shop) => ScrapedCatalogue(
  id: id,
  retailerId: shop,
  title: id,
  sourceUrl: 'https://example.com/$id',
  validFrom: DateTime(2026, 11, 23),
  validTo: DateTime(2026, 12, 6),
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
    catalogues: [cat('s1', 'shoprite'), cat('p1', 'picknpay')],
    errors: <String, String>{},
  );
  Future<ScrapeResult> shopriteRefuses() async => (
    catalogues: [cat('p2', 'picknpay')],
    errors: {'shoprite': 'HTTP 403'},
  );

  test('a shop that refuses today is filled in from the last good run', () async {
    await scrapeWithMemory(file, allGood, now: DateTime(2026, 11, 27, 6));
    final r = await scrapeWithMemory(
      file,
      shopriteRefuses,
      now: DateTime(2026, 11, 28, 6),
    );
    expect(r.errors, isEmpty);
    expect(r.catalogues.map((c) => c.id), unorderedEquals(['p2', 's1']));
    final s1 = r.catalogues.firstWhere((c) => c.id == 's1');
    expect(s1.validTo, DateTime(2026, 12, 6));
    expect(s1.ocrImageUrls, ['https://example.com/s1/p1.jpg']);
  });

  test('the stand-in is still there on the third day', () async {
    await scrapeWithMemory(file, allGood, now: DateTime(2026, 11, 27, 6));
    await scrapeWithMemory(file, shopriteRefuses, now: DateTime(2026, 11, 28, 6));
    final r = await scrapeWithMemory(
      file,
      shopriteRefuses,
      now: DateTime(2026, 11, 30, 5),
    );
    expect(r.errors, isEmpty);
  });

  test('a shop out of reach for too long is reported', () async {
    await scrapeWithMemory(file, allGood, now: DateTime(2026, 11, 27, 6));
    final r = await scrapeWithMemory(
      file,
      shopriteRefuses,
      now: DateTime(2026, 12, 1, 6),
    );
    expect(r.errors.keys, ['shoprite']);
    expect(r.catalogues.map((c) => c.id), ['p2']);
  });

  test('with nothing remembered the failure stands', () async {
    final r = await scrapeWithMemory(file, shopriteRefuses);
    expect(r.errors.keys, ['shoprite']);
  });
}
