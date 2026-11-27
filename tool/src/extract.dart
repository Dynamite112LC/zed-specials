// Turns the text found on a leaflet page into priced items.
//
// OCR gives loose lines of text with positions. Each shop lays its leaflets
// out differently, so each has its own reader that finds the price flashes
// and then attaches the description, pack size and saving printed around
// them. Anything that cannot be read with reasonable certainty is left out:
// a missing item is better than a wrong price.
import 'dart:math' as math;

class OcrLine {
  OcrLine(this.t, this.x, this.y, this.w, this.h, this.th, this.s);

  final String t;
  final double x, y, w, h;

  /// Text height, corrected for tilt.
  final double th;

  /// Recognition confidence, 0..1.
  final double s;

  double get right => x + w;
  double get bottom => y + h;
  double get cx => x + w / 2;
  double get cy => y + h / 2;

  @override
  String toString() => '"$t" @${x.round()},${y.round()}';
}

/// A price found by its colours rather than by general OCR (see
/// find_flashes in tool/ocr.py): the full-size kwacha digits and the small
/// raised ngwee, each read on its own.
class PriceFlash {
  PriceFlash({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.th,
    required this.kwacha,
    required this.ngwee,
    required this.ks,
    required this.ns,
    required this.raised,
  });

  final double x, y, w, h;

  /// Height of the full-size digits.
  final double th;
  final String kwacha, ngwee;

  /// Recognition confidence of each part, 0..1.
  final double ks, ns;

  /// How many small raised glyphs follow the kwacha digits.
  final int raised;

  factory PriceFlash.fromJson(Map<String, dynamic> j) => PriceFlash(
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    w: (j['w'] as num).toDouble(),
    h: (j['h'] as num).toDouble(),
    th: (j['th'] as num).toDouble(),
    kwacha: j['kwacha'] as String,
    ngwee: j['ngwee'] as String? ?? '',
    ks: (j['ks'] as num).toDouble(),
    ns: (j['ns'] as num?)?.toDouble() ?? 0,
    raised: j['raised'] as int? ?? 0,
  );
}

class OcrPage {
  OcrPage(this.width, this.height, this.lines, {this.flashes = const []});

  final int width, height;
  final List<OcrLine> lines;
  final List<PriceFlash> flashes;

  /// [flashes] is the content of the page's ".flashes.json", when it has one.
  factory OcrPage.fromJson(
    Map<String, dynamic> j, {
    Map<String, dynamic>? flashes,
  }) => OcrPage(
    j['width'] as int,
    j['height'] as int,
    flashes: [
      for (final f in (flashes?['flashes'] as List? ?? const []))
        PriceFlash.fromJson(f as Map<String, dynamic>),
    ],
    [
      for (final l in j['lines'] as List)
        OcrLine(
          (l['t'] as String).trim(),
          (l['x'] as num).toDouble(),
          (l['y'] as num).toDouble(),
          (l['w'] as num).toDouble(),
          (l['h'] as num).toDouble(),
          (l['th'] as num).toDouble(),
          (l['s'] as num).toDouble(),
        ),
    ],
  );
}

class CropBox {
  const CropBox(this.x, this.y, this.w, this.h);
  final int x, y, w, h;
}

class ExtractedItem {
  ExtractedItem({
    required this.name,
    required this.price,
    required this.crop,
    this.perKg = false,
    this.sizeQty,
    this.sizeUnit,
    this.save,
    this.confidence = 1,
    this.bundle = false,
    this.parts = const [],
    this.agreed = false,
    this.otherPrice,
    this.firstName,
    this.assumedNgwee = false,
  });

  /// True when the raised ngwee were seen but could not be read, and ".99"
  /// was assumed.
  final bool assumedNgwee;

  /// True when the second reader (see second_reader.dart) gave this price
  /// too.
  final bool agreed;

  /// The price the second reader gave, when it gave another one.
  final double? otherPrice;

  /// The name as first read, when the second reading repaired it.
  final String? firstName;

  /// This item after the second reader has had its say. A size is only
  /// replaced when one is given.
  ExtractedItem copyWith({
    required String name,
    double? price,
    String? firstName,
    double? sizeQty,
    String? sizeUnit,
    bool agreed = false,
    double? otherPrice,
  }) => ExtractedItem(
    name: name,
    price: price ?? this.price,
    crop: crop,
    perKg: perKg,
    sizeQty: sizeQty ?? this.sizeQty,
    sizeUnit: sizeQty != null ? sizeUnit : this.sizeUnit,
    save: save,
    confidence: confidence,
    bundle: bundle,
    parts: parts,
    agreed: agreed,
    otherPrice: otherPrice,
    firstName: firstName,
  );

  final String name;
  final double price;
  final bool perKg;

  /// Several different products sold together for one price.
  final bool bundle;

  /// The price and the description lines this item was read from.
  final List<OcrLine> parts;

  /// The part of the page that shows the whole item: its picture, its
  /// price and its description. For looking at what was actually printed.
  CropBox regionOn(int pageWidth, int pageHeight) {
    var x0 = crop.x.toDouble(), y0 = crop.y.toDouble();
    var x1 = x0 + crop.w, y1 = y0 + crop.h;
    for (final l in parts) {
      x0 = math.min(x0, l.x);
      y0 = math.min(y0, l.y);
      x1 = math.max(x1, l.right);
      y1 = math.max(y1, l.bottom);
    }
    final pad = 0.012 * pageWidth;
    x0 = math.max(0, x0 - pad);
    y0 = math.max(0, y0 - pad);
    x1 = math.min(pageWidth.toDouble(), x1 + pad);
    y1 = math.min(pageHeight.toDouble(), y1 + pad);
    return CropBox(
      x0.round(),
      y0.round(),
      math.max(2, (x1 - x0).round()),
      math.max(2, (y1 - y0).round()),
    );
  }

  final double? sizeQty;
  final String? sizeUnit;
  final double? save;
  final double confidence;
  final CropBox crop;
}

List<ExtractedItem> extractItems(String retailerId, OcrPage page) {
  // The OCR model also knows Chinese and now and then "reads" a picture as
  // CJK text. Those lines are never real on these leaflets.
  final lines = page.lines
      .where(
        (l) =>
            l.s >= 0.5 &&
            l.t.isNotEmpty &&
            !RegExp(
              r'[^\x00-\u024F\u2010-\u2027\u2030-\u203A\u20AC\u2122]',
            ).hasMatch(l.t),
      )
      .toList();
  final List<ExtractedItem> items;
  switch (retailerId) {
    case 'shoprite':
      items = _readShoprite(page, lines);
    case 'picknpay':
      items = _readPicknPay(page, lines);
    case 'game':
      items = _readGame(page, lines);
    default:
      items = const [];
  }
  return items.where(_plausible).toList();
}

bool _plausible(ExtractedItem i) {
  if (i.price < 1 || i.price > 250000) return false;
  // A real description has at least two proper words; a lone word is
  // nearly always a fragment of packaging text.
  final words = RegExp(r'[A-Za-z]{3,}').allMatches(i.name).length;
  if (words < 2) return false;
  if (i.name.length > 110) return false;
  if (RegExp(
    r'^(\d+-piece )?per set$|^at selected stores?$|^also available',
    caseSensitive: false,
  ).hasMatch(i.name)) {
    return false;
  }
  return i.confidence >= 0.7;
}

// ----------------------------------------------------------------- helpers

double _median(Iterable<double> values, {double fallback = 20}) {
  final v = values.toList()..sort();
  return v.isEmpty ? fallback : v[v.length ~/ 2];
}

int _letters(String s) => RegExp(r'[A-Za-z]').allMatches(s).length;

bool _mostlyUpper(String s) {
  final upper = RegExp(r'[A-Z]').allMatches(s).length;
  final lower = RegExp(r'[a-z]').allMatches(s).length;
  return upper >= 3 && upper >= 2 * lower;
}

/// Distance between the nearest edges of two boxes; 0 when they overlap.
double _gap(OcrLine a, OcrLine b) {
  final dx = math.max(0.0, math.max(a.x - b.right, b.x - a.right));
  final dy = math.max(0.0, math.max(a.y - b.bottom, b.y - a.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

/// Reading order: top to bottom, then left to right within a row.
String _joinLines(List<OcrLine> lines) {
  final sorted = [...lines]
    ..sort((a, b) {
      final rowTol = 0.6 * math.min(a.th, b.th);
      if ((a.cy - b.cy).abs() <= rowTol) return a.x.compareTo(b.x);
      return a.cy.compareTo(b.cy);
    });
  return sorted.map((l) => l.t).join(' ');
}

// Case matters for the short units: "4G" and "64GB" are not weights.
final _sizeRe = RegExp(
  r'(?:(\d+)\s?[xX]\s?)?(\d+(?:[.,]\d+)?)\s?(kg|KG|Kg|g|ml|ML|Ml|ltr|Ltr|LTR|lt|[Ll]itres?|l|L)\b',
);
final _countRe = RegExp(
  r"\b(\d+)\s?(?:'?s|pack|pk|pcs|per pack|rolls|sheets)\b",
  caseSensitive: false,
);

/// Finds a pack size in [text] and normalises it to g, ml or a count.
(double, String)? parseSize(String text) {
  final m = _sizeRe.firstMatch(text);
  if (m != null) {
    final multi = m.group(1) == null ? 1 : int.parse(m.group(1)!);
    var qty = double.parse(m.group(2)!.replaceAll(',', '.')) * multi;
    final unit = m.group(3)!.toLowerCase();
    if (unit == 'kg') return (qty * 1000, 'g');
    if (unit == 'g') return (qty, 'g');
    if (unit == 'ml') return (qty, 'ml');
    return (qty * 1000, 'ml');
  }
  final c = _countRe.firstMatch(text);
  if (c != null) {
    final n = double.parse(c.group(1)!);
    if (n >= 2 && n <= 500) return (n, 'ea');
  }
  return null;
}

/// Repairs the commonest misreadings of pack sizes: "750mi", "Skg", "Tkg".
String _fixOcrUnits(String s) => s
    .replaceAllMapped(
      RegExp(r'(\d)\s?m[i1!]\b', caseSensitive: false),
      (m) => '${m[1]}ml',
    )
    .replaceAll(RegExp(r'\bSkg\b', caseSensitive: false), '5kg')
    .replaceAll(RegExp(r'\b[TI]kg\b'), '1kg')
    .replaceAllMapped(RegExp(r'(\d)[oO]g\b'), (m) => '${m[1]}0g')
    // "1.5 LAssorted": the unit ran into the next word.
    .replaceAllMapped(
      RegExp(r'(\d)\s?L([A-Z][a-z])'),
      (m) => '${m[1]}L ${m[2]}',
    );

const _keepUpper = {
  'TV',
  'LED',
  'UHD',
  'HD',
  'USB',
  'LG',
  'JBL',
  'HP',
  'UHT',
  'IQF',
  'BBQ',
  'BMX',
  'XL',
  'DVD',
  'AA',
  'AAA',
  'PNP',
  'KIC',
  'SMEG',
  'NRB',
  'RTD',
  'A4',
};
const _keepLower = {
  'kg',
  'g',
  'ml',
  'l',
  'ltr',
  'x',
  'or',
  'and',
  'in',
  'with',
  'per',
  'of',
  'the',
  'for',
};

/// Tidies a description: fixes spacing, drops selling words, and turns
/// SHOUTED leaflet text into normal capitalisation.
String cleanName(String raw) {
  // Game lists features and a stock number after a bullet: keep the name.
  final cut = RegExp(
    r'\s*[·•]|\s*\bItem no\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (cut != null && cut.start > 8) raw = raw.substring(0, cut.start);
  var s = _fixOcrUnits(raw)
      // "EACH" misread or run into the word before it.
      .replaceAll(
        RegExp(r'\b(S?EA?CH|SECH|EAH|EAC)\b', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}')
      .replaceAll(
        RegExp(
          r'\b(EACH|PER PACK|PER SET|PER PAIR|PER KG|EA)\b\.?',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\bALL VARIANTS\b', caseSensitive: false), 'Assorted')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  s = s.replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9)%]+$'), '');

  // Leaflets SHOUT. Whole descriptions in capitals are fully re-cased;
  // otherwise only the shouted words (usually the brand) are.
  final shouted = _mostlyUpper(s);
  s = s
      .split(' ')
      .map((w) {
        if (w.isEmpty) return w;
        final bare = w.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        if (_keepUpper.contains(bare.toUpperCase())) return w.toUpperCase();
        if (RegExp(r'\d').hasMatch(w)) return shouted ? w.toLowerCase() : w;
        final isCaps = bare.length >= 2 && bare == bare.toUpperCase();
        if (!isCaps) return w;
        if (!shouted && bare.length < 4) return w;
        final lower = w.toLowerCase();
        if (_keepLower.contains(lower)) return lower;
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
  // "500 g" -> "500g" keeps sizes compact and consistent.
  s = s.replaceAllMapped(
    RegExp(r'(\d)\s+(kg|g|ml|ltr|l)\b', caseSensitive: false),
    (m) => '${m[1]}${m[2]!.toLowerCase()}',
  );
  // Litres read better with a capital: "2L", not "2l" (which looks like 21).
  s = s.replaceAllMapped(RegExp(r'(\d)l\b'), (m) => '${m[1]}L');
  if (s.isNotEmpty) s = s[0].toUpperCase() + s.substring(1);
  return s;
}

CropBox _cropAround(OcrPage page, double left, double top, double w, double h) {
  final x = left.clamp(0, page.width - 2).round();
  final y = top.clamp(0, page.height - 2).round();
  final cw = math.min(w, page.width - x.toDouble()).round();
  final ch = math.min(h, page.height - y.toDouble()).round();
  return CropBox(x, y, math.max(cw, 2), math.max(ch, 2));
}

double _confidence(OcrLine price, List<OcrLine> desc) {
  final d = desc.isEmpty
      ? 0.0
      : desc.map((l) => l.s).reduce((a, b) => a + b) / desc.length;
  // Big stylised price lettering scores lower than plain text even when it
  // is read correctly, so it gets some allowance.
  return math.min(math.min(1.0, price.s + 0.15), d);
}

/// Gives each description line to the closest price that [accepts] it.
Map<T, List<OcrLine>> _assign<T>(
  List<OcrLine> candidates,
  List<T> prices,
  double? Function(OcrLine line, T price) cost,
) {
  final out = <T, List<OcrLine>>{for (final p in prices) p: []};
  for (final line in candidates) {
    T? best;
    double? bestCost;
    for (final p in prices) {
      final c = cost(line, p);
      if (c == null) continue;
      if (bestCost == null || c < bestCost) {
        best = p;
        bestCost = c;
      }
    }
    if (best != null) out[best]!.add(line);
  }
  return out;
}

// ---------------------------------------------------------------- Shoprite
//
// Yellow flash with a big whole-kwacha price ("K35"), "SAVE K18" above it,
// and the description in small capitals underneath:
//
//      SAVE K18
//        K35
//   MAX 6 PER CUSTOMER
//   BUTTERCUP
//   MARGARINE 500g EACH

final _shopritePrice = RegExp(
  r'''^[Kk"'“”‘’*«]?\s?(\d{1,5})(?:[.,](\d{2}))?$''',
);
final _shopriteNoise = RegExp(
  r'^(MAX\b.*CUSTOMER|SAVE\b.*|ONLY AT.*|.*DAYS ONLY|PAGE \d+|T&C.*|WHILE STOCKS.*|NOT FOR SALE.*|.*DRINK RESPONSIBLY.*|.*TO SUNDAY|.*PERSONS UNDER.*|AT SELECTED STORES?|ALSO AVAILABLE.*|.*NOT INCLUDED.*|SCAN FOR.*|ALSO|AVAILABLE+|IN SELECTED STORES ONLY|SELECTED|STORES ONLY|SELECTED STORES ONLY|RADIO-?|CONTROLLED|BOTH FOR|ALL FOR|(?:BUY\s?)?(?:ANY\s?)?\d{1,2}\s?FOR|(?:GET\s)?ALL\s?\d+\s?FOR|FREE\b.*|LOWER PRICES.*|LOOK\b.*|.*YOU CAN TRUST.*)$',
  caseSensitive: false,
);

/// "ANY 2 FOR", "3 FOR": the price printed underneath buys that many.
final _multiBuy = RegExp(
  r'^(?:BUY\s?)?(?:ANY\s?)?(\d{1,2})\s?FOR$',
  caseSensitive: false,
);

/// "BOTH FOR", "ALL 4 FOR": different products sold together.
final _bundleFlag = RegExp(
  r'^(?:GET\s)?(?:BOTH|ALL(?:\s?\d+)?)\s?FOR$',
  caseSensitive: false,
);

final _sizeBadge = RegExp(
  r'^(?:\d+\s?[xX]\s?)?\d+(?:[.,]\d+)?\s?(kg|g|ml|l|e|s)$',
  caseSensitive: false,
);

/// Shoprite prints whole kwacha on some leaflets ("K35") and raised ngwee on
/// others ("K12" with a small "99"). OCR reads the second kind as "K1299",
/// or as "K129" when it misses a digit, so the width of the box is used to
/// tell full-size digits from raised ones.
Map<OcrLine, (double, bool)> _shopriteValues(
  List<OcrLine> prices,
  List<OcrLine> lines, {
  bool ngweeHint = false,
}) {
  double bigWidth(String digits) {
    var w = 0.0;
    for (final c in digits.split('')) {
      w += c == '1' ? 0.33 : 0.6;
    }
    return w;
  }

  const raisedPair = 0.35;
  final small = lines.where((l) => RegExp(r'^\d{2}$').hasMatch(l.t)).toList();

  OcrLine? raisedFor(OcrLine p) {
    for (final l in small) {
      if (l.th < 0.25 * p.th || l.th > 0.62 * p.th) continue;
      if (l.x < p.cx || l.x > p.right + 0.5 * p.th) continue;
      if (l.y < p.y - 0.3 * p.th || l.cy > p.cy + 0.1 * p.th) continue;
      return l;
    }
    return null;
  }

  String digitsOf(OcrLine p) => _shopritePrice.firstMatch(p.t)!.group(1)!;
  double kOf(OcrLine p) => RegExp(r'^\d').hasMatch(p.t) ? 0 : 0.62;
  bool looksRaised(OcrLine p, String digits) {
    final ratio = p.w / p.th;
    final whole = kOf(p) + bigWidth(digits);
    final raised =
        kOf(p) + bigWidth(digits.substring(0, digits.length - 2)) + raisedPair;
    return (ratio - raised).abs() <= (ratio - whole).abs();
  }

  // Does this page print ngwee at all?
  final ngweePage =
      ngweeHint ||
      prices.any((p) {
        final d = digitsOf(p);
        return raisedFor(p) != null || (d.length >= 4 && looksRaised(p, d));
      });

  final out = <OcrLine, (double, bool)>{};
  for (final p in prices) {
    final m = _shopritePrice.firstMatch(p.t)!;
    final digits = m.group(1)!;
    if (m.group(2) != null) {
      out[p] = (double.parse(digits) + int.parse(m.group(2)!) / 100, true);
      continue;
    }
    final raised = raisedFor(p);
    if (raised != null) {
      // The raised "99" is small and often comes back as "66".
      final ngwee = raised.t == '66' ? 99 : int.parse(raised.t);
      out[p] = (double.parse(digits) + ngwee / 100, true);
    } else if (digits.length >= 4 && looksRaised(p, digits)) {
      out[p] = (
        double.parse(digits.substring(0, digits.length - 2)) +
            int.parse(digits.substring(digits.length - 2)) / 100,
        true,
      );
    } else if (digits.length == 3 && ngweePage && digits.endsWith('9')) {
      // "K43" + "99" read as "K439": one raised digit was missed.
      final ratio = p.w / p.th;
      final whole = kOf(p) + bigWidth(digits);
      final dropped = kOf(p) + bigWidth(digits.substring(0, 2)) + raisedPair;
      if ((ratio - dropped).abs() < (ratio - whole).abs()) {
        out[p] = (double.parse(digits.substring(0, 2)) + 0.99, false);
      } else {
        out[p] = (double.parse(digits), true);
      }
    } else if (ngweePage &&
        digits.length >= 4 &&
        digits.endsWith('9') &&
        !digits.endsWith('99')) {
      // "K134" + "99" read as "K1349": one raised digit was missed.
      out[p] = (
        double.parse(digits.substring(0, digits.length - 1)) + 0.99,
        false,
      );
    } else {
      out[p] = (double.parse(digits), true);
    }
  }
  return out;
}

/// A stack of description lines: "ZEUS QUAD BIKE / RIDE-ON / EACH".
class _TextBlock {
  _TextBlock(OcrLine first) : lines = [first];

  final List<OcrLine> lines;

  /// Set once the block has reached its "EACH" or "PER SET".
  bool closed = false;

  double get x => lines.map((l) => l.x).reduce(math.min);
  double get y => lines.map(_top).reduce(math.min);
  double get right => lines.map((l) => l.right).reduce(math.max);
  double get bottom => lines.map(_bottom).reduce(math.max);
  double get cx => (x + right) / 2;
  bool get ended => lines.any((l) => _descriptionEnd.hasMatch(l.t));
}

// The box of a tilted line (starburst prices and their descriptions are
// set at an angle) is much taller than its lettering. These give the
// extent of the lettering itself.
double _top(OcrLine l) => l.cy - l.th / 2;
double _bottom(OcrLine l) => l.cy + l.th / 2;

/// Shoprite ends a description with what the price buys.
final _descriptionEnd = RegExp(
  r'(EACH|EAH|\bPER\s?(SET|KG|PACK|BAG|PAIR|ROLL|TRAY|BOX|CASE|BUNCH|PUNNET|DOZEN|LITRE|METRE|m))\.?\s*$',
  caseSensitive: false,
);

List<ExtractedItem> _readShoprite(OcrPage page, List<OcrLine> lines) {
  final caps = lines
      .where((l) => _letters(l.t) >= 6 && _mostlyUpper(l.t))
      .toList();
  final body = _median(
    caps.where((l) => !_shopriteNoise.hasMatch(l.t)).map((l) => l.th),
    fallback: page.height / 120,
  );

  // Prices found by their colours come first: both parts of the price are
  // read exactly there. General OCR supplies the rest (the starburst
  // prices, which are not red on yellow).
  final values = <OcrLine, (double, bool)>{};
  final prices = <OcrLine>[];
  // Prices whose raised ngwee were seen but not read.
  final assumed = <OcrLine>{};

  // What general OCR made of the big price lettering, for cross-checking.
  final readPrices = lines
      .where(
        (l) => l.th >= 2.6 * body && l.s >= 0.6 && _shopritePrice.hasMatch(l.t),
      )
      .toList();
  bool centreInside(
    double cx,
    double cy,
    double x,
    double y,
    double r,
    double b,
    double pad,
  ) => cx > x - pad && cx < r + pad && cy > y - pad && cy < b + pad;

  // The same flash can be found twice (once per colour scheme): keep the
  // better reading. Largest first, so a fragment never displaces a whole.
  final found = [...page.flashes]
    ..sort((a, b) => (b.w * b.h).compareTo(a.w * a.h));
  final kept = <PriceFlash>[];
  for (final f in found) {
    if (f.ks < 0.8) continue;
    final twin = kept.any(
      (k) => centreInside(
        f.x + f.w / 2,
        f.y + f.h / 2,
        k.x,
        k.y,
        k.x + k.w,
        k.y + k.h,
        0,
      ),
    );
    if (!twin) kept.add(f);
  }

  for (final f in kept) {
    if (f.th < 1.5 * body) continue;
    final kwacha = int.tryParse(f.kwacha);
    if (kwacha == null) continue;
    // Starburst prices have outlined digits that the colour reader only
    // catches part of ("6" of "K56"). Where general OCR read the whole
    // number there, it is the one to believe.
    final fuller = readPrices.any((l) {
      final digits = _shopritePrice.firstMatch(l.t)!.group(1)!;
      return f.raised == 0 &&
          digits.length > f.kwacha.length &&
          digits.contains(f.kwacha) &&
          centreInside(
            f.x + f.w / 2,
            f.y + f.h / 2,
            l.x,
            l.y,
            l.right,
            l.bottom,
            0.2 * l.th,
          );
    });
    if (fuller) continue;
    var certain = f.ks >= 0.85;
    var score = f.ks;
    double value = kwacha.toDouble();
    if (f.raised > 0) {
      var ngwee = RegExp(r'^\d{2}$').hasMatch(f.ngwee)
          ? int.parse(f.ngwee)
          : null;
      // The raised "99" is small and now and then comes back as "66".
      if (ngwee == 66) ngwee = 99;
      if (ngwee == null) {
        // Raised digits were seen but not read: nearly always 99.
        ngwee = 99;
        certain = false;
      } else {
        score = math.min(score, f.ns);
      }
      value += ngwee / 100;
    }
    final line = OcrLine('K${f.kwacha}', f.x, f.y, f.w, f.h, f.th, score);
    prices.add(line);
    values[line] = (value, certain);
    if (f.raised > 0 && !RegExp(r'^\d{2}$').hasMatch(f.ngwee)) {
      assumed.add(line);
    }
  }
  final flashes = [...prices];
  // [pad] in price heights: generous when asking whether OCR read the same
  // price, none when asking whether a line of text is printed on the flash
  // (a starburst's description sits right under its big digits).
  bool onFlash(OcrLine l, {double pad = 0.3}) => flashes.any(
    (f) =>
        l.cx > f.x - pad * f.th &&
        l.cx < f.right + pad * f.th &&
        l.cy > f.y - pad * f.th &&
        l.cy < f.bottom + pad * f.th,
  );
  final read = readPrices.where((l) => !onFlash(l)).toList();
  // Whether this leaflet prints ngwee at all, as told by the flashes.
  final withNgwee = kept.where((f) => f.raised > 0).length;
  values.addAll(
    _shopriteValues(
      read,
      lines,
      ngweeHint: kept.length >= 3 && withNgwee >= 0.6 * kept.length,
    ),
  );
  prices.addAll(read);
  if (prices.isEmpty) return const [];

  final desc = lines.where((l) {
    if (prices.contains(l) || onFlash(l, pad: 0)) return false;
    if (l.th < 0.6 * body || l.th > 1.8 * body) return false;
    if (_shopriteNoise.hasMatch(l.t)) return false;
    final perKg = RegExp(r'^per\s?kg$', caseSensitive: false).hasMatch(l.t);
    return perKg || (_letters(l.t) >= 3 && _mostlyUpper(l.t));
  }).toList()..sort((a, b) => _top(a).compareTo(_top(b)));

  OcrLine? nearestPrice(OcrLine l) {
    OcrLine? best;
    var bestGap = double.infinity;
    for (final p in prices) {
      // By centres: a description is centred under its price, or starts
      // beside it, while a wide neighbour can come closer edge to edge.
      final g = (l.cx - p.cx).abs() + 0.5 * (l.cy - p.cy).abs();
      if (g < bestGap) {
        bestGap = g;
        best = p;
      }
    }
    return best;
  }

  // Stack the description lines into blocks. A block is finished by its
  // "EACH" or "PER SET", so two products printed one above the other stay
  // apart.
  final blocks = <_TextBlock>[];
  for (final l in desc) {
    _TextBlock? home;
    var nearest = double.infinity;
    for (final b in blocks) {
      final last = b.lines.last;
      final ratio = l.th / last.th;
      if (ratio < 0.7 || ratio > 1.45) continue;
      // The rest of a line that OCR split in two. On a crowded page the
      // next product's description starts on the same row, a space away:
      // that one belongs to another price.
      final sameRow =
          (l.cy - last.cy).abs() < 0.5 * l.th &&
          l.x - last.right > -0.3 * l.th &&
          l.x - last.right < 1.5 * l.th &&
          identical(nearestPrice(l), nearestPrice(last));
      if (sameRow) {
        home = b;
        break;
      }
      if (b.closed) continue;
      final gap = _top(l) - b.bottom;
      if (gap < -0.5 * l.th || gap > 0.75 * l.th) continue;
      // Lines of one description share a left edge (set beside a price)
      // or a centre (set under one). The neighbouring product's lines,
      // level with these on a crowded page, share neither.
      final wide = math.max(l.w, b.right - b.x);
      final flushLeft = (l.x - b.x).abs() < 0.8 * l.th;
      final centred = (l.cx - b.cx).abs() < 0.8 * l.th + 0.12 * wide;
      if (!flushLeft && !centred) continue;
      if (gap.abs() < nearest) {
        nearest = gap.abs();
        home = b;
      }
    }
    if (home == null) {
      home = _TextBlock(l);
      blocks.add(home);
    } else {
      home.lines.add(l);
    }
    if (_descriptionEnd.hasMatch(l.t)) home.closed = true;
  }

  // Pair each price with one block, closest pairs first. Food leaflets put
  // the description under the price; the leaflets for toys and household
  // goods put it beside the price or just above it.
  final pairs = <(double, OcrLine, _TextBlock)>[];
  for (final p in prices) {
    final unit = p.th;
    final pTop = _top(p), pBottom = _bottom(p);
    for (final b in blocks) {
      // Stray capitals from the packaging come as a lone line with no
      // "EACH" to end it.
      if (!b.ended && b.lines.length < 2) continue;
      double? cost;
      void consider(double c) {
        if (cost == null || c < cost!) cost = c;
      }

      // Underneath, roughly centred.
      final below = b.y - pBottom;
      if (below > -0.35 * unit && below < 1.5 * unit) {
        final reach = math.min(1.3 * unit, 5 * body);
        if (b.right > p.x - reach && b.x < p.right + reach) {
          consider(math.max(0, below) + 0.25 * (b.cx - p.cx).abs());
        }
      }
      // To the right, starting level with the price.
      final beside = b.x - p.right;
      if (beside > -0.25 * unit &&
          beside < 1.0 * unit &&
          b.y > pTop - 0.7 * unit &&
          b.y < pBottom) {
        consider(math.max(0, beside) + 0.5 * (b.y - pTop).abs());
      }
      // Just above, starting over the price.
      final above = pTop - b.bottom;
      if (above > -0.2 * unit &&
          above < 0.8 * unit &&
          b.x > p.x - 1.0 * unit &&
          b.x < p.right + 0.5 * unit) {
        consider(math.max(0, above) + 0.25 * (b.x - p.x).abs() + 0.4 * unit);
      }
      if (cost == null) continue;
      // A real description ends with "EACH" or the like; stray capitals
      // from the packaging do not.
      if (!b.ended) cost = cost! + 0.6 * unit;
      pairs.add((cost!, p, b));
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  final blockOf = <OcrLine, _TextBlock>{};
  final taken = <_TextBlock>{};
  for (final (_, p, b) in pairs) {
    if (blockOf.containsKey(p) || taken.contains(b)) continue;
    blockOf[p] = b;
    taken.add(b);
  }

  final saves = lines
      .where((l) => RegExp(r'^SAVE', caseSensitive: false).hasMatch(l.t))
      .toList();

  // Size badges printed on the product photo, each given to the one price
  // it sits above.
  final badgeByPrice = _assign<OcrLine>(
    lines.where((l) => _sizeBadge.hasMatch(l.t)).toList(),
    prices,
    (b, p) {
      if (b.cy > p.y || p.y - b.bottom > 4.2 * p.th) return null;
      if (b.right < p.x - 1.5 * p.th || b.x > p.right + 2.2 * p.th) return null;
      return _gap(b, p);
    },
  );

  final flags = lines
      .where((l) => _multiBuy.hasMatch(l.t) || _bundleFlag.hasMatch(l.t))
      .toList();

  final items = <ExtractedItem>[];
  for (final p in prices) {
    final own = blockOf[p]?.lines;
    if (own == null) continue;
    final raw = _joinLines(own);
    final (total, certain) = values[p]!;

    // "ANY 2 FOR" sits right on top of the price it belongs to.
    var price = total;
    var name = cleanName(raw);
    var bundle = false;
    var count = 1;
    for (final f in flags) {
      if (f.right < p.x || f.x > p.right) continue;
      if ((p.y - f.bottom).abs() > 0.9 * f.th) continue;
      final m = _multiBuy.firstMatch(f.t);
      final n = m == null ? 0 : int.parse(m.group(1)!);
      if (n > 1) {
        // Show the price of one, as the other shops' leaflets do.
        final whole = total == total.roundToDouble();
        // The leaflet words the size for the lot ("2x50g"): name one pack.
        name = name.replaceFirst(RegExp('\\b$n\\s?[xX]\\s?(?=\\d)'), '');
        name = '$name ($n for K${total.toStringAsFixed(whole ? 0 : 2)})';
        price = double.parse((total / n).toStringAsFixed(2));
        count = n;
      } else if (m == null) {
        bundle = true;
      }
    }
    final multi = price != total;

    // "SAVE K18" or "SAVE 50%" printed just above the price.
    double? save;
    for (final s in saves) {
      if (s.cy > p.cy || _gap(s, p) > 0.8 * p.th) continue;
      final sm = RegExp(
        r'SAVE\s*K?\s*(\d+)\s*(%)?',
        caseSensitive: false,
      ).firstMatch(s.t);
      if (sm == null) continue;
      final n = double.parse(sm.group(1)!);
      save = sm.group(2) == null ? n : total * n / (100 - n);
      if (sm.group(2) != null) save = save.roundToDouble();
    }

    // A "saving" several times the price means the price was misread.
    if (save != null && save > 2.5 * total) continue;
    // A saving on several packs says nothing about the price of one.
    if (multi) save = null;

    final perKg = RegExp(r'per\s?kg', caseSensitive: false).hasMatch(raw);
    var sizeText = _fixOcrUnits(raw);
    var size = perKg ? null : parseSize(sizeText);
    if (size == null && !perKg) {
      // Fall back to the size badge printed on the product photo above.
      OcrLine? nearest;
      for (final b in badgeByPrice[p]!) {
        if (nearest == null || _gap(b, p) < _gap(nearest, p)) nearest = b;
      }
      if (nearest != null) {
        // The litre sign is a script "l" that OCR reads as "e".
        sizeText = nearest.t.replaceAll(
          RegExp(r'e$', caseSensitive: false),
          'l',
        );
        size = parseSize(sizeText);
      }
    }
    // "2x50g" under "ANY 2 FOR" is the size of the lot; the price is now
    // for one pack, so the size must be too.
    if (size != null &&
        count > 1 &&
        RegExp('\\b$count\\s?[xX]\\s?\\d').hasMatch(sizeText)) {
      size = (size.$1 / count, size.$2);
    }

    // Hero prices are printed much larger than the products they sit on.
    final unit = math.min(p.th, 4.6 * body);
    final half = math.max(1.9 * unit, p.w * 0.6);
    items.add(
      ExtractedItem(
        name: name,
        price: price,
        perKg: perKg,
        sizeQty: size?.$1,
        sizeUnit: size?.$2,
        save: save,
        bundle: bundle,
        parts: [p, ...own],
        assumedNgwee: assumed.contains(p),
        confidence: certain ? _confidence(p, own) : 0.8 * _confidence(p, own),
        // The product photo sits above the price flash.
        crop: _cropAround(
          page,
          p.cx - half,
          p.y - 0.3 * unit - 3.2 * unit,
          2 * half,
          3.2 * unit,
        ),
      ),
    );
  }
  return items;
}

// -------------------------------------------------------------- Pick n Pay
//
// Black panel: big kwacha digits with the ngwee raised beside them, "Each"
// under the ngwee, then the description in white:
//
//   SAVE          188 99
//    21               Each
//          Meru Gold Cooking
//               Oil 5Ltr

class _PnpPrice {
  _PnpPrice(this.main, this.value, this.left, this.right, this.certain);

  final OcrLine main;
  final double value;
  final double left, right;

  /// False when the ngwee had to be guessed.
  final bool certain;

  double get cx => (left + right) / 2;
}

/// Width a string of big digits should take, in multiples of its height.
double _digitsWidth(String digits) {
  var w = 0.0;
  for (final c in digits.split('')) {
    w += c == '1' ? 0.45 : 0.75;
  }
  return w;
}

List<ExtractedItem> _readPicknPay(OcrPage page, List<OcrLine> lines) {
  final wordy = lines
      .where((l) => _letters(l.t) >= 8 && !_mostlyUpper(l.t) && l.s > 0.9)
      .toList();
  final body = _median(wordy.map((l) => l.th), fallback: page.height / 85);

  final digitLines = lines
      .where((l) => RegExp(r'^\d{1,6}$').hasMatch(l.t))
      .toList();
  final saveWords = lines.where((l) => l.t.toUpperCase() == 'SAVE').toList();

  bool isSaveNumber(OcrLine l) => saveWords.any(
    (s) =>
        l.y >= s.y &&
        l.y - s.bottom < 0.6 * l.th &&
        l.cx > s.x - s.w * 0.3 &&
        l.cx < s.right + s.w * 0.3,
  );

  final big = digitLines
      .where((l) => l.th >= 2.4 * body && !isSaveNumber(l))
      .toList();

  final prices = <_PnpPrice>[];
  for (final b in big) {
    // Raised ngwee: two small digits at the top right of the big ones.
    OcrLine? ngwee;
    for (final l in digitLines) {
      if (identical(l, b) || l.t.length != 2) continue;
      if (l.th < 0.35 * b.th || l.th > 0.8 * b.th) continue;
      if (l.x < b.cx || l.x > b.right + 0.5 * b.th) continue;
      if (l.y < b.y - 0.3 * b.th || l.cy > b.cy + 0.1 * b.th) continue;
      ngwee = l;
    }
    var digits = b.t;
    if (ngwee != null) {
      // The big box sometimes swallows one raised digit ("129" read as
      // "1299"): trim until the digits fit the box.
      while (digits.length > 1 && _digitsWidth(digits) * b.th > b.w * 1.2) {
        digits = digits.substring(0, digits.length - 1);
      }
      prices.add(
        _PnpPrice(
          b,
          double.parse(digits) + int.parse(ngwee.t) / 100,
          b.x,
          ngwee.right,
          true,
        ),
      );
    } else if (digits.length >= 3 &&
        // Read as one run. If the box is too narrow for every digit to be
        // full size, its last two digits are the raised ngwee.
        ((_digitsWidth(digits.substring(0, digits.length - 2)) + 0.62) * b.th -
                    b.w)
                .abs() <=
            (_digitsWidth(digits) * b.th - b.w).abs()) {
      prices.add(
        _PnpPrice(
          b,
          double.parse(digits.substring(0, digits.length - 2)) +
              int.parse(digits.substring(digits.length - 2)) / 100,
          b.x,
          b.right,
          true,
        ),
      );
    } else {
      prices.add(_PnpPrice(b, double.parse(digits), b.x, b.right, false));
    }
  }
  if (prices.isEmpty) return const [];

  final priceLines = {for (final p in prices) p.main};
  final desc = lines.where((l) {
    if (priceLines.contains(l)) return false;
    if (l.th < 0.7 * body || l.th > 1.45 * body) return false;
    if (_letters(l.t) < 2 && parseSize(l.t) == null) return false;
    // Descriptions are in normal case; capitals are section headings and
    // "SMART SHOPPER PRICE" flags.
    if (_mostlyUpper(l.t) && _letters(l.t) > 5) return false;
    return !RegExp(
      r'^(each|per\s?kg|save|for\s?\d|promotion valid.*|smart shopper.*)$',
      caseSensitive: false,
    ).hasMatch(l.t);
  }).toList();

  final assigned = _assign<_PnpPrice>(desc, prices, (line, p) {
    final dy = line.y - p.main.bottom;
    if (dy < -0.25 * p.main.th || dy > 1.25 * p.main.th) return null;
    if ((line.cx - p.cx).abs() > 1.25 * p.main.th) return null;
    return dy.abs() + (line.cx - p.cx).abs();
  });
  // Keep the lines that follow on from the price without a break.
  final byPrice = <_PnpPrice, List<OcrLine>>{};
  assigned.forEach((p, list) {
    list.sort((a, b) => a.y.compareTo(b.y));
    final own = <OcrLine>[];
    for (final l in list) {
      if (own.isNotEmpty) {
        final lowest = own.map((o) => o.bottom).reduce(math.max);
        if (l.y - lowest > 0.9 * body) break;
      }
      own.add(l);
    }
    byPrice[p] = own;
  });

  final perKgLines = lines
      .where((l) => RegExp(r'^per\s?kg$', caseSensitive: false).hasMatch(l.t))
      .toList();
  final forLines = lines
      .where((l) => RegExp(r'^FOR\s?(\d)$', caseSensitive: false).hasMatch(l.t))
      .toList();

  final items = <ExtractedItem>[];
  for (final p in prices) {
    final own = byPrice[p]!;
    if (own.isEmpty) continue;
    final raw = _joinLines(own);
    final b = p.main;

    var price = p.value;
    var name = cleanName(raw);
    // "21.00 FOR 2": show the price of one.
    for (final f in forLines) {
      if (f.x > b.cx && f.x < p.right + b.th && (f.cy - b.cy).abs() < b.th) {
        final n = int.parse(RegExp(r'\d').firstMatch(f.t)!.group(0)!);
        if (n > 1) {
          name = '$name ($n for K${price.toStringAsFixed(0)})';
          price = price / n;
        }
      }
    }

    final perKg = perKgLines.any(
      (l) => l.x > b.x && l.x < p.right + b.th && (l.cy - b.cy).abs() < b.th,
    );

    // The saving sits in a badge at the top left of the product's cell.
    double? save;
    for (final s in saveWords) {
      if (s.y > b.y || b.y - s.y > 6.5 * b.th) continue;
      if (s.x > b.x || b.x - s.x > 2.4 * b.th) continue;
      for (final n in digitLines) {
        if (n.y >= s.y &&
            n.y - s.bottom < 0.6 * n.th &&
            n.cx > s.x - s.w * 0.3 &&
            n.cx < s.right + s.w * 0.3) {
          save = double.parse(n.t);
        }
      }
    }
    if (save != null && save >= price * 4) save = null;

    final size = parseSize(raw);
    final width = math.max(3.6 * b.th, p.right - p.left + 1.2 * b.th);
    items.add(
      ExtractedItem(
        name: name,
        price: price,
        perKg: perKg,
        sizeQty: size?.$1,
        sizeUnit: size?.$2,
        save: save,
        parts: [b, ...own],
        confidence: p.certain ? _confidence(b, own) : 0.8 * _confidence(b, own),
        // The product photo sits above and to the left of the price panel.
        crop: _cropAround(
          page,
          p.cx - width * 0.62,
          b.y - 3.5 * b.th,
          width,
          3.4 * b.th,
        ),
      ),
    );
  }
  return items;
}

// -------------------------------------------------------------------- Game

//
// A tidy left-aligned block of text (brand, product, size) with the price to
// its right or just under it. The ngwee are raised: "K34" + "99".
//
//   KELLOGG'S           K34 99
//   Instant Noodles        Each
//   5 x 70 g Assorted

class _Block {
  _Block(OcrLine first) : lines = [first];

  final List<OcrLine> lines;

  double get x => lines.map((l) => l.x).reduce(math.min);
  double get y => lines.first.y;
  double get right => lines.map((l) => l.right).reduce(math.max);
  double get bottom => lines.last.bottom;
}

class _GamePrice {
  _GamePrice(this.main, this.value, this.right, this.certain);

  final OcrLine main;
  final double value;
  final double right;
  final bool certain;
}

final _gamePrice = RegExp(r'^[Kk]\s?(\d[\d ]{0,8})$');

List<ExtractedItem> _readGame(OcrPage page, List<OcrLine> lines) {
  final wordy = lines.where((l) => _letters(l.t) >= 8 && l.s > 0.9).toList();
  final body = _median(wordy.map((l) => l.th), fallback: page.height / 105);

  final digitLines = lines
      .where((l) => RegExp(r'^\d{2}$').hasMatch(l.t))
      .toList();

  final prices = <_GamePrice>[];
  for (final l in lines) {
    final m = _gamePrice.firstMatch(l.t);
    if (m == null || l.th < 1.5 * body) continue;
    final digits = m.group(1)!.replaceAll(' ', '');

    OcrLine? ngwee;
    for (final d in digitLines) {
      if (d.th < 0.35 * l.th || d.th > 0.85 * l.th) continue;
      if (d.x < l.cx || d.x > l.right + 0.4 * l.th) continue;
      if (d.y < l.y - 0.3 * l.th || d.cy > l.cy + 0.15 * l.th) continue;
      ngwee = d;
    }
    // Width a "K" plus [big] full-size and [small] raised digits would take.
    double widthOf(String big, int small) {
      var w = 0.65; // the K
      for (final c in big.split('')) {
        w += c == '1' ? 0.4 : 0.65;
      }
      return (w + small * 0.25) * l.th;
    }

    if (ngwee != null) {
      // The main box sometimes swallows a raised digit ("K59" read as
      // "K599"): trim until the digits fit the box.
      var whole = digits;
      while (whole.length > 1 && widthOf(whole, 0) > l.w * 1.18) {
        whole = whole.substring(0, whole.length - 1);
      }
      prices.add(
        _GamePrice(
          l,
          double.parse(whole) + int.parse(ngwee.t) / 100,
          ngwee.right,
          true,
        ),
      );
      continue;
    }

    // One run of digits: decide from the width of the box whether its last
    // two digits are the small raised ngwee or full-size kwacha digits.

    if (digits.length >= 3) {
      final asNgwee = widthOf(digits.substring(0, digits.length - 2), 2);
      final asWhole = widthOf(digits, 0);
      if ((asNgwee - l.w).abs() <= (asWhole - l.w).abs()) {
        prices.add(
          _GamePrice(
            l,
            double.parse(digits.substring(0, digits.length - 2)) +
                int.parse(digits.substring(digits.length - 2)) / 100,
            l.right,
            true,
          ),
        );
        continue;
      }
    }
    // No raised ngwee. Appliances are priced in whole kwacha ("K13999"),
    // and there the box is as wide as its digits; a box wider than that
    // had ngwee that were not read, though the kwacha amount is right.
    final fits = (widthOf(digits, 0) - l.w).abs() <= 0.15 * l.w;
    prices.add(_GamePrice(l, double.parse(digits), l.right, fits));
  }
  if (prices.isEmpty) return const [];

  final priceLines = {for (final p in prices) p.main};
  final candidates = lines.where((l) {
    if (priceLines.contains(l)) return false;
    // Brand names are set a little larger than the rest of a description.
    if (l.th < 0.72 * body || l.th > 1.75 * body) return false;
    // A logo read as text comes back as a low-scoring jumble.
    if (l.s < 0.6) return false;
    if (_letters(l.t) < 2 && parseSize(l.t) == null) return false;
    return !RegExp(
      r'^(each|per\s?kg|save.*|was\b.*|now\b.*|t&c.*|while stocks.*|black friday.*)$',
      caseSensitive: false,
    ).hasMatch(l.t);
  }).toList()..sort((a, b) => _top(a).compareTo(_top(b)));

  // Stack lines into left-aligned blocks. Boxes of neighbouring lines often
  // overlap a little, so the lettering's own extent is used.
  final blocks = <_Block>[];
  for (final l in candidates) {
    _Block? home;
    for (final b in blocks) {
      final last = b.lines.last;
      final gap = _top(l) - _bottom(last);
      final ratio = l.th / last.th;
      if ((l.x - last.x).abs() <= 0.7 * math.max(l.th, last.th) &&
          gap > -0.5 * l.th &&
          gap < 0.9 * l.th &&
          ratio > 0.6 &&
          ratio < 1.65) {
        home = b;
      }
    }
    if (home == null) {
      blocks.add(_Block(l));
    } else {
      home.lines.add(l);
    }
  }

  // The whole price box: "NOW" above the price and "SAVE 161" under it.
  final labels = lines
      .where(
        (l) =>
            RegExp(r'^(now|save\s?\d+)$', caseSensitive: false).hasMatch(l.t),
      )
      .toList();
  (double, double) boxOf(OcrLine m) {
    var top = _top(m), bottom = _bottom(m);
    for (final l in labels) {
      if (l.right < m.x - 0.3 * m.th || l.x > m.right + 0.3 * m.th) continue;
      if (_bottom(l) <= m.cy && _top(m) - _bottom(l) < 0.6 * m.th) {
        top = math.min(top, _top(l));
      }
      if (_top(l) >= m.cy && _top(l) - _bottom(m) < 0.6 * m.th) {
        bottom = math.max(bottom, _bottom(l));
      }
    }
    return (top, bottom);
  }

  // Pair each price with its nearest block, closest pairs first. Groceries
  // have the description to the left of the price; appliances have it
  // above or below the price box.
  final pairs = <(double, _GamePrice, _Block)>[];
  for (final p in prices) {
    final m = p.main;
    final unit = m.th;
    final (boxTop, boxBottom) = boxOf(m);
    // A price with "NOW" or "SAVE" on it is the appliance style, whose
    // description sits above or below. On a plain grocery price, text
    // above it is far more likely to be print on the packaging.
    final plain = boxTop == _top(m) && boxBottom == _bottom(m);
    final offAxis = plain ? 0.6 * unit : 0.0;
    for (final b in blocks) {
      double? cost;
      void consider(double c) {
        if (cost == null || c < cost!) cost = c;
      }

      final bTop = _top(b.lines.first), bBottom = _bottom(b.lines.last);
      final shift = (b.x - m.x).abs();
      final overlapsAcross =
          b.right > m.x - 0.5 * unit && b.x < p.right + 0.5 * unit;

      // Block to the left of the price, level with it.
      final hGap = m.x - b.right;
      if (hGap > -0.3 * unit &&
          hGap < 3.2 * unit &&
          bTop < boxBottom + 0.5 * unit &&
          bBottom > boxTop - 0.5 * unit) {
        consider(math.max(0, hGap).toDouble());
      }
      // Block just above the price box.
      final above = boxTop - bBottom;
      if (above > -0.4 * unit &&
          above < 1.2 * unit &&
          (shift < 1.5 * unit || overlapsAcross)) {
        consider(math.max(0, above) + 0.3 * shift + offAxis);
      }
      // Block just under the price box.
      final below = bTop - boxBottom;
      if (below > -0.4 * unit &&
          below < 1.0 * unit &&
          (shift < 1.5 * unit || overlapsAcross)) {
        consider(math.max(0, below) + 0.3 * shift + 0.3 * unit + offAxis);
      }
      if (cost == null) continue;
      // Real descriptions are neat stacks of clearly printed lines. Stray
      // words from the packaging are single lines, often poorly read.
      if (b.lines.length == 1) cost = cost! + 1.5 * unit;
      final score =
          b.lines.map((l) => l.s).reduce((x, y) => x + y) / b.lines.length;
      cost = cost! + (1 - score) * 3 * unit;
      pairs.add((cost!, p, b));
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));

  final bullet = RegExp(
    r'^\s*[·•*▪■\-–]\s?\S|^\s*Item no\b',
    caseSensitive: false,
  );
  final usedPrices = <_GamePrice>{};
  final usedBlocks = <_Block>{};
  final items = <ExtractedItem>[];
  for (final (_, p, b) in pairs) {
    if (usedPrices.contains(p) || usedBlocks.contains(b)) continue;
    usedPrices.add(p);
    usedBlocks.add(b);

    // The name is what comes before the list of features and the stock
    // number ("· Fixed handlebars", "· Item no: 850001329").
    final firstBullet = b.lines.indexWhere((l) => bullet.hasMatch(l.t));
    final named = firstBullet > 0 ? b.lines.sublist(0, firstBullet) : b.lines;
    final raw = named.map((l) => l.t).join(' ');
    final m = p.main;
    final size = parseSize(raw);
    final left = math.min(b.x, m.x);
    final top = math.min(b.y, m.y);
    final right = math.max(b.right, p.right);
    final width = math.max(right - left + 0.4 * m.th, 4.6 * m.th);
    items.add(
      ExtractedItem(
        name: cleanName(raw),
        price: p.value,
        sizeQty: size?.$1,
        sizeUnit: size?.$2,
        parts: [m, ...b.lines],
        confidence: p.certain
            ? _confidence(m, named)
            : 0.8 * _confidence(m, named),
        // The product photo sits above the description.
        crop: _cropAround(
          page,
          left - 0.2 * m.th,
          top - 4.2 * m.th,
          width,
          4.1 * m.th,
        ),
      ),
    );
  }
  return items;
}

// -------------------------------------------------------------- categories

// Checked in this order, so "Body Cream" is personal care before "cream"
// can make it dairy, and "Milk Chocolate Slab" is a snack before "milk".
const _categories = <String, List<String>>{
  'Toys': [
    'doll',
    'dolls',
    'toy',
    'toys',
    'play set',
    'tea set',
    'kitchen set',
    'beauty set',
    'make-up set',
    'racing car',
    'friction',
    'die-cast',
    'ride-on',
    'dump truck',
    'plastic truck',
    'construction truck',
    'robots',
    'figurine',
    'plush',
    'teddy',
    'puzzle',
    'building blocks',
    'bmx',
    'radio-controlled',
    'remote-control',
    'battery-operated',
    'car set',
    'water gun',
    'board game',
  ],
  'Electronics & appliances': [
    'tv',
    'television',
    'fridge',
    'freezer',
    'phone',
    'laptop',
    'kettle',
    'iron',
    'microwave',
    'speaker',
    'speakers',
    'stove',
    'blender',
    'fan',
    'heater',
    'washing machine',
    'soundbar',
    'tablet',
    'printer',
    'headphones',
    'earbuds',
    'fryer',
    'cooker',
    'toaster',
    'decoder',
    'inverter',
    'solar',
    'generator',
    'smartphone',
    'refrigerator',
    'vacuum',
    'oven',
    'hob',
    'power bank',
    'console',
    'monitor',
    'air conditioner',
    'clipper',
    'hair cutting',
    'laminator',
    'laminating',
    'hood',
    'ryzen',
    'intel',
    'smart tank',
    'sandwich maker',
    'box set',
    'chest freezer',
  ],
  'Home & outdoor': [
    'mattress',
    'bed',
    'chair',
    'table',
    'pots',
    'pan',
    'bicycle',
    'christmas',
    'lights',
    'duvet',
    'blanket',
    'pillow',
    'towel',
    'luggage',
    'suitcase',
    'tent',
    'pool',
    'trampoline',
    'tyre',
    'drill',
    'paint',
    'cutlery',
    'dinner set',
    'storage',
    'couch',
    'sofa',
    'wardrobe',
    'curtain',
    'ladder',
    'cookware',
    'comforter',
    'stroller',
    'scooter',
    'umbrella',
    'patio',
    'cot',
    'bouncer',
    'fry combo',
    'camping',
    'dinnerware',
    'casserole',
    'flask',
    'cooler box',
    'bedding',
    'glass',
    'glasses',
    'tumbler',
    'bowl',
    'bowls',
    'dispenser',
    'roaster',
    'dinner set',
    'armchair',
    'padlock',
    'mortise lock',
    'batteries',
  ],
  'Baby & personal care': [
    'diapers',
    'nappies',
    'lotion',
    'toothpaste',
    'shampoo',
    'pads',
    'wipes',
    'deodorant',
    'roll-on',
    'roll on',
    'petroleum',
    'vaseline',
    'colgate',
    'razor',
    'sanitary',
    'conditioner',
    'bath',
    'body',
    'showergel',
    'deo',
    'liners',
    'hand soap',
    'antiseptic',
    'repellent',
  ],
  'Liquor': [
    'beer',
    'wine',
    'whisky',
    'whiskey',
    'lager',
    'cider',
    'vodka',
    'gin',
    'brandy',
    'castle',
    'mosi',
    'amarula',
    'rum',
    'liqueur',
    'spritzer',
    'savanna',
    'heineken',
    'corona',
  ],
  'Household': [
    'washing',
    'detergent',
    'soap',
    'tissue',
    'toilet',
    'bleach',
    'cleaner',
    'dishwashing',
    'softener',
    'polish',
    'insecticide',
    'doom',
    'candles',
    'matches',
    'foil',
    'refuse',
    'air freshener',
    'paper towel',
    'scouring',
    'cleaning',
    'laundry',
    'pine gel',
    'car care',
  ],
  'Snacks & sweets': [
    'chips',
    'biscuits',
    'biscuit',
    'cookies',
    'chocolate',
    'sweets',
    'curls',
    'crisps',
    'wafers',
    'snacks',
    'snack',
    'popcorn',
    'slab',
    'candy',
    'lollipop',
    'jelly',
    'marshmallows',
    'eclairs',
    'peanuts',
    'chews',
    'shortbread',
    'marie',
  ],
  'Drinks': [
    'juice',
    'drink',
    'drinks',
    'coke',
    'fanta',
    'sprite',
    'water',
    'squash',
    'cordial',
    'energy',
    'cola',
    'soda',
    'nectar',
    'mazoe',
    'pepsi',
    'mirinda',
    'milkshake',
    'milk shake',
  ],
  'Pantry': [
    'rice',
    'sugar',
    'oil',
    'flour',
    'meal',
    'beans',
    'pasta',
    'noodles',
    'sauce',
    'salt',
    'tea',
    'teabags',
    'coffee',
    'cereal',
    'oats',
    'jam',
    'peanut butter',
    'macaroni',
    'spaghetti',
    'soup',
    'spice',
    'spices',
    'curry',
    'mayonnaise',
    'ketchup',
    'honey',
    'bread',
    'corn flakes',
    'creamer',
    'soya',
    'soy',
    'stock',
    'vinegar',
    'porridge',
    'gravy',
    'syrup',
    'yeast',
    'custard',
    'mealie',
    'samp',
    'lentils',
    'tomato',
    'cocoa',
    'mchuzi',
    'ricoffy',
    'paste',
  ],
  'Meat & fish': [
    'chicken',
    'beef',
    'mince',
    'sausage',
    'wors',
    'pork',
    'steak',
    'fish',
    'polony',
    'bacon',
    'vienna',
    'burger',
    'drumstick',
    'tuna',
    'pilchard',
    'pilchards',
    'kapenta',
    'chops',
    'goat',
    'lamb',
    'hungarian',
    'russian',
    'corned',
    'bream',
    'gizzard',
    'liver',
    'hake',
  ],
  'Dairy & eggs': [
    'milk',
    'cheese',
    'yoghurt',
    'yogurt',
    'butter',
    'margarine',
    'spread',
    'eggs',
    'cream',
    'maas',
    'lacto',
  ],
  'Fruit & veg': [
    'apples',
    'onions',
    'potatoes',
    'tomatoes',
    'bananas',
    'oranges',
    'cabbage',
    'carrots',
    'grapes',
    'lemons',
    'avocado',
    'peppers',
  ],
};

/// Puts an item in a shopping category from the words in its name.
String categorise(String name) {
  final n = ' ${name.toLowerCase()} ';
  for (final entry in _categories.entries) {
    for (final word in entry.value) {
      if (RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(n)) {
        return entry.key;
      }
    }
  }
  return 'Other';
}
