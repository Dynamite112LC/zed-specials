// Reads the public specials pages of each retailer and lists the catalogues
// currently published. Pure Dart (package:http only) so the feed builder and,
// later, the mobile app can both use it.
import 'dart:convert';

import 'package:http/http.dart' as http;

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

class ScrapedCatalogue {
  ScrapedCatalogue({
    required this.id,
    required this.retailerId,
    required this.title,
    required this.sourceUrl,
    this.coverUrl,
    this.validFrom,
    this.validTo,
    this.stores,
    this.viewImageUrls = const [],
    this.ocrImageUrls = const [],
    this.pdfUrl,
  });

  final String id;
  final String retailerId;
  final String title;
  final String sourceUrl;
  final String? coverUrl;
  final DateTime? validFrom;
  final DateTime? validTo;
  final String? stores;

  /// Page images sized for reading on a phone.
  final List<String> viewImageUrls;

  /// The largest page images available, used for reading prices.
  final List<String> ocrImageUrls;

  /// Set when the catalogue is only published as a PDF.
  final String? pdfUrl;
}

Future<String> _get(http.Client client, String url) async {
  final res = await client
      .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
      .timeout(const Duration(seconds: 45));
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', Uri.parse(url));
  }
  return utf8.decode(res.bodyBytes, allowMalformed: true);
}

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#038;', '&')
    .replaceAll('&#8211;', '–')
    .replaceAll('&#8217;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"');

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

int? _month(String? name) {
  if (name == null || name.length < 3) return null;
  return _months[name.substring(0, 3).toLowerCase()];
}

/// Parses ranges such as "27 – 29 Nov 2026", "24 Nov – 03 Dec 2026",
/// "26 November - 02 December 2026" and "26nov29nov2026".
(DateTime?, DateTime?) parseDateRange(String text) {
  final m = RegExp(
    r'(\d{1,2})\s*([A-Za-z]{3,9})?\s*(?:–|-|to)?\s*(\d{1,2})\s*([A-Za-z]{3,9})\s*(\d{4})',
  ).firstMatch(text);
  if (m == null) return (null, null);
  final year = int.parse(m.group(5)!);
  final toMonth = _month(m.group(4));
  if (toMonth == null) return (null, null);
  final fromMonth = _month(m.group(2)) ?? toMonth;
  final to = DateTime(year, toMonth, int.parse(m.group(3)!));
  final from = DateTime(
    fromMonth > toMonth ? year - 1 : year,
    fromMonth,
    int.parse(m.group(1)!),
  );
  return (from, to);
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

// ---------------------------------------------------------------- Shoprite

/// Shoprite lists leaflets per store; without a store it shows the default
/// Lusaka store (Cairo Road).
Future<List<ScrapedCatalogue>> scrapeShoprite(http.Client client) async {
  const listUrl = 'https://www.shoprite.co.zm/specials.html';
  final html = await _get(client, listUrl);
  final out = <ScrapedCatalogue>[];

  final chunks = html.split('cmp-leaflets-specials__leaflets__item ').skip(1);
  for (final chunk in chunks) {
    final viewer = RegExp(
      r'data-leaflet-external-url="([^"]+)"',
    ).firstMatch(chunk)?.group(1);
    if (viewer == null) continue;
    final cover = RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(chunk)?.group(1);
    final ts = RegExp(
      r'data-valid-until-timestamp="(\d+)"',
    ).firstMatch(chunk)?.group(1);

    final base = viewer.substring(0, viewer.lastIndexOf('/'));
    final slug = base.substring(base.lastIndexOf('/') + 1);

    var (from, to) = parseDateRange(slug);
    if (ts != null) {
      // The timestamp is 23:59 Zambian time (UTC+2) on the last day.
      final end = DateTime.fromMillisecondsSinceEpoch(
        int.parse(ts),
        isUtc: true,
      ).add(const Duration(hours: 2));
      to = DateTime(end.year, end.month, end.day);
    }

    var title = 'Specials';
    final view = <String>[];
    final ocr = <String>[];
    try {
      final index = await _get(client, viewer);
      final rawTitle = RegExp(
        r'<title>([^<]+)</title>',
      ).firstMatch(index)?.group(1);
      if (rawTitle != null) {
        var t = _decodeEntities(rawTitle).trim();
        t = t.replaceFirst(RegExp(r'^Shoprite\s+', caseSensitive: false), '');
        final cut = t.toLowerCase().indexOf(' zambia');
        if (cut > 0) t = t.substring(0, cut);
        if (t.isNotEmpty) title = t;
      }

      final pager =
          jsonDecode(await _get(client, '$base/files/assets/pager.js'))
              as Map<String, dynamic>;
      final pages = pager['pages'] as Map<String, dynamic>;
      final defaults = pages['defaults'] as Map<String, dynamic>;
      final sizes = (defaults['substrateSizes'] as List).cast<int>();
      final ready = (defaults['substrateSizesReady'] as int?) ?? sizes.length;
      var viewIdx = 1;
      for (var i = 0; i < sizes.length && i < ready; i++) {
        if (sizes[i] <= 1400) viewIdx = i + 1;
      }
      final ext = (defaults['substrateFormat'] as String?) ?? 'jpg';
      for (final n in (pages['structure'] as List).cast<String>()) {
        final page = n.padLeft(4, '0');
        final stem = '$base/files/assets/common/page-html5-substrates/page$page';
        view.add('${stem}_$viewIdx.$ext');
        ocr.add('${stem}_$ready.$ext');
      }
    } catch (_) {
      // Viewer layout changed: keep the catalogue with its cover only.
    }

    out.add(
      ScrapedCatalogue(
        id: 'shoprite-$slug',
        retailerId: 'shoprite',
        title: title,
        sourceUrl: viewer,
        coverUrl: cover == null
            ? null
            : Uri.parse(listUrl).resolve(cover).toString(),
        validFrom: from,
        validTo: to,
        stores: 'Lusaka stores (Cairo Road leaflet)',
        viewImageUrls: view,
        ocrImageUrls: ocr,
      ),
    );
  }
  return out;
}

// -------------------------------------------------------------- Pick n Pay

Future<List<ScrapedCatalogue>> scrapePicknPay(http.Client client) async {
  const listUrl = 'https://www.picknpayzambia.com/specials/';
  final html = await _get(client, listUrl);
  final out = <ScrapedCatalogue>[];

  for (final chunk in html.split('<article id="post-').skip(1)) {
    final link = RegExp(
      r'href="([^"]+\.pdf)"[^>]*>([^<]+)</a>\s*</h',
    ).firstMatch(chunk);
    if (link == null) continue;
    final pdf = link.group(1)!;
    final title = _decodeEntities(link.group(2)!).trim();
    final cover = RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(chunk)?.group(1);
    final validText = RegExp(
      r'Prices Valid:\s*</b>\s*([^<]+)',
    ).firstMatch(chunk)?.group(1);
    final stores = RegExp(
      r'Selected stores</b>\s*([^<]+)<',
    ).firstMatch(chunk)?.group(1);
    final (from, to) = validText == null
        ? (null, null)
        : parseDateRange(_decodeEntities(validText));

    final file = Uri.parse(pdf).pathSegments.last.replaceAll('.pdf', '');
    out.add(
      ScrapedCatalogue(
        id: 'picknpay-${_slug(file)}',
        retailerId: 'picknpay',
        title: title,
        sourceUrl: pdf,
        coverUrl: cover,
        validFrom: from,
        validTo: to,
        stores: stores == null
            ? null
            : _decodeEntities(
                stores,
              ).trim().replaceAll(RegExp(r',\s*$'), ''),
        pdfUrl: pdf,
      ),
    );
  }
  return out;
}

// -------------------------------------------------------------------- Game

/// Game Zambia's site embeds its catalogue from Guzzle.
Future<List<ScrapedCatalogue>> scrapeGame(http.Client client) async {
  const embedUrl = 'https://www.guzzle.co.za/embed/catalogue/GameZambia';
  final html = await _get(client, embedUrl);

  final heading = RegExp(r'<h1[^>]*>([^<]+)</h1>').firstMatch(html)?.group(1);
  if (heading == null) return const [];
  final full = _decodeEntities(heading).trim();
  var title = full.replaceFirst(RegExp(r'^Game Zambia\s*:\s*'), '');
  final paren = title.indexOf('(');
  final (from, to) = parseDateRange(paren >= 0 ? title.substring(paren) : full);
  if (paren > 0) title = title.substring(0, paren).trim();

  final byPage = <int, String>{};
  String? groupId;
  final re = RegExp(
    r'(https://media\.guzzle\.co\.za/thumbnails/catalogue-pages/(\d+)/[\w-]+-p(\d+)-cropped\.jpg)',
  );
  for (final m in re.allMatches(html)) {
    groupId ??= m.group(2);
    if (m.group(2) != groupId) continue;
    byPage.putIfAbsent(int.parse(m.group(3)!), () => m.group(1)!);
  }
  if (byPage.isEmpty) return const [];
  final pages = byPage.keys.toList()..sort();

  return [
    ScrapedCatalogue(
      id: 'game-$groupId',
      retailerId: 'game',
      title: title.isEmpty ? 'Specials' : title,
      sourceUrl: 'http://www.game.co.zm/promotions/promotions',
      coverUrl: '${byPage[pages.first]}.900x10000_q76.jpg',
      validFrom: from,
      validTo: to,
      stores: 'All Game Zambia stores',
      viewImageUrls: [
        for (final p in pages) '${byPage[p]}.1240x10000_q90.webp',
      ],
      ocrImageUrls: [
        for (final p in pages) '${byPage[p]}.1800x10000_q90.webp',
      ],
    ),
  ];
}

/// Runs every scraper; one failing site does not stop the others.
Future<({List<ScrapedCatalogue> catalogues, Map<String, String> errors})>
scrapeAll(http.Client client) async {
  final scrapers = {
    'shoprite': scrapeShoprite,
    'picknpay': scrapePicknPay,
    'game': scrapeGame,
  };
  final catalogues = <ScrapedCatalogue>[];
  final errors = <String, String>{};
  for (final entry in scrapers.entries) {
    try {
      catalogues.addAll(await entry.value(client));
    } catch (e) {
      errors[entry.key] = '$e';
    }
  }
  return (catalogues: catalogues, errors: errors);
}
