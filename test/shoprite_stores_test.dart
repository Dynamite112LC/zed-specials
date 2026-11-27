import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zed_specials/src/models.dart';
import 'package:zed_specials/src/scrape/scrapers.dart';
import 'package:zed_specials/src/shoprite_stores.dart';

String listing(List<String> slugs) => [
  '<html><body>',
  for (final s in slugs)
    '<div class="cmp-leaflets-specials__leaflets__item x" '
        'data-leaflet-external-url="https://specials.shoprite.co.zm/deals/$s/index.html" '
        'data-valid-until-timestamp="1796594340000"><img src="/cover-$s.jpg"></div>',
  '</body></html>',
].join();

final pager = jsonEncode({
  'pages': {
    'defaults': {
      'substrateSizes': [650, 960, 1350, 2050],
      'substrateSizesReady': 4,
      'substrateFormat': 'jpg',
    },
    'structure': ['1', '2'],
  },
});

void main() {
  setUp(() {
    politePause = Duration.zero;
    retryPauses = const [];
  });

  test('one store stands for each province and kind of shop', () {
    final areas = shopriteAreaStores;
    expect(areas.map((s) => s.area).toSet(), hasLength(areas.length));
    expect(
      areas.map((s) => s.area).toSet(),
      {for (final s in shopriteStores) s.area},
    );
    // Far fewer requests than one per store.
    expect(areas.length, lessThan(shopriteStores.length ~/ 2));
  });

  test('describes where a leaflet applies', () {
    final all = {for (final s in shopriteStores) s.area};
    final liquor = all.where((a) => a.endsWith('LiquorShop')).toSet();
    final supermarkets = all.difference(liquor);

    expect(describeShopriteAreas(all), 'All Shoprite stores');
    expect(describeShopriteAreas(supermarkets), 'All Shoprite supermarkets');
    expect(describeShopriteAreas(liquor), 'Shoprite LiquorShop stores');
    expect(
      describeShopriteAreas(['298|Shoprite', '298|Shoprite Select']),
      'Shoprite and Shoprite Select stores in Copperbelt',
    );
    expect(describeShopriteAreas(const []), 'Shoprite stores');
  });

  test('reads each area and merges a leaflet listed in several', () async {
    final asked = <String>[];
    final client = MockClient((request) async {
      final url = request.url;
      if (url.host == 'www.shoprite.co.zm') {
        final store = shopriteStoreById(
          int.parse(url.queryParameters['storeId']!),
        )!;
        asked.add(store.area);
        expect(url.queryParameters['provinceId'], '${store.provinceId}');
        if (store.brand == 'Shoprite LiquorShop') {
          return http.Response(listing(['zmliquor23nov06dec2026']), 200);
        }
        return http.Response(
          listing([
            'zmfestive23nov06dec2026',
            // Something only the Copperbelt gets.
            if (store.provinceId == 298) 'zmcopperbelt23nov29nov2026',
          ]),
          200,
        );
      }
      if (url.path.endsWith('pager.js')) return http.Response(pager, 200);
      return http.Response(
        '<title>Shoprite Festive Season Zambia 23 November</title>',
        200,
      );
    });

    final found = await scrapeShoprite(client);
    expect(asked.toSet(), {for (final s in shopriteStores) s.area});
    expect(asked, hasLength(shopriteAreaStores.length), reason: 'once each');

    final byId = {for (final c in found) c.id: c};
    expect(byId.keys, {
      'shoprite-zmfestive23nov06dec2026',
      'shoprite-zmcopperbelt23nov29nov2026',
      'shoprite-zmliquor23nov06dec2026',
    });

    final festive = byId['shoprite-zmfestive23nov06dec2026']!;
    expect(festive.stores, 'All Shoprite supermarkets');
    expect(festive.ocrImageUrls, hasLength(2));
    expect(festive.title, 'Festive Season');

    final regional = byId['shoprite-zmcopperbelt23nov29nov2026']!;
    expect(regional.areas.every((a) => a.startsWith('298|')), isTrue);
    expect(regional.stores, contains('Copperbelt'));

    expect(
      byId['shoprite-zmliquor23nov06dec2026']!.stores,
      'Shoprite LiquorShop stores',
    );
  });

  test('a refusal on the first store stops the scan', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('Request blocked', 403);
    });
    await expectLater(scrapeShoprite(client), throwsA(anything));
    expect(requests, 1, reason: 'no hammering a site that says no');
  });

  test('a catalogue applies everywhere unless it names areas', () {
    Catalogue cat(List<String> areas) => Catalogue(
      id: 'c',
      retailerId: 'shoprite',
      title: 't',
      sourceUrl: 'u',
      pages: const [],
      areas: areas,
    );
    final ndola = shopriteStores.firstWhere((s) => s.name == 'Ndola');
    expect(cat(const []).appliesTo(ndola.area), isTrue);
    expect(cat(['298|Shoprite']).appliesTo(ndola.area), isTrue);
    expect(cat(['301|Shoprite']).appliesTo(ndola.area), isFalse);
    // No store chosen: everything shows.
    expect(cat(['301|Shoprite']).appliesTo(null), isTrue);
  });
}
