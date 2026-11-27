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

class OcrPage {
  OcrPage(this.width, this.height, this.lines);

  final int width, height;
  final List<OcrLine> lines;

  factory OcrPage.fromJson(Map<String, dynamic> j) => OcrPage(
    j['width'] as int,
    j['height'] as int,
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
  });

  final String name;
  final double price;
  final bool perKg;

  /// Several different products sold together for one price.
  final bool bundle;
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
            !RegExp(r'[^\x00-ɏ‘-‟]').hasMatch(l.t),
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

const _keepUpper = {'TV', 'LED', 'UHD', 'HD', 'USB', 'LG', 'JBL', 'HP', 'UHT', 'IQF', 'BBQ', 'XL', 'DVD', 'AA', 'AAA', 'PNP', 'KIC', 'SMEG', 'NRB', 'RTD', 'A4'};
const _keepLower = {'kg', 'g', 'ml', 'l', 'ltr', 'x', 'or', 'and', 'in', 'with', 'per', 'of', 'the', 'for'};

/// Tidies a description: fixes spacing, drops selling words, and turns
/// SHOUTED leaflet text into normal capitalisation.
String cleanName(String raw) {
  // Game lists features and a stock number after a bullet: keep the name.
  final cut = RegExp(r'\s*[·•]|\s*\bItem no\b', caseSensitive: false)
      .firstMatch(raw);
  if (cut != null && cut.start > 8) raw = raw.substring(0, cut.start);
  var s = _fixOcrUnits(raw)
      // "EACH" misread or run into the word before it.
      .replaceAll(RegExp(r'\b(S?EA?CH|SECH|EAH|EAC)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}')
      .replaceAll(RegExp(r'\b(EACH|PER PACK|PER KG|EA)\b\.?', caseSensitive: false), ' ')
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

final _shopritePrice = RegExp(r'''^[Kk"'“”‘’*«]?\s?(\d{1,5})(?:[.,](\d{2}))?$''');
final _shopriteNoise = RegExp(
  r'^(MAX\b.*CUSTOMER|SAVE\b.*|ONLY AT.*|.*DAYS ONLY|PAGE \d+|T&C.*|WHILE STOCKS.*|NOT FOR SALE.*|.*DRINK RESPONSIBLY.*|.*TO SUNDAY|.*PERSONS UNDER.*|AT SELECTED STORES?|ALSO AVAILABLE.*|.*NOT INCLUDED.*|SCAN FOR.*|BOTH FOR|ALL FOR|(?:BUY\s?)?(?:ANY\s?)?\d{1,2}\s?FOR|(?:GET\s)?ALL\s?\d+\s?FOR|FREE\b.*|LOWER PRICES.*|LOOK\b.*|.*YOU CAN TRUST.*)$',
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
  List<OcrLine> lines,
) {
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
  final ngweePage = prices.any((p) {
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
    } else {
      out[p] = (double.parse(digits), true);
    }
  }
  return out;
}

List<ExtractedItem> _readShoprite(OcrPage page, List<OcrLine> lines) {
  final caps = lines
      .where((l) => _letters(l.t) >= 6 && _mostlyUpper(l.t))
      .toList();
  final body = _median(
    caps.where((l) => !_shopriteNoise.hasMatch(l.t)).map((l) => l.th),
    fallback: page.height / 120,
  );

  final prices = lines
      .where(
        (l) =>
            l.th >= 2.6 * body && l.s >= 0.6 && _shopritePrice.hasMatch(l.t),
      )
      .toList();
  if (prices.isEmpty) return const [];
  final values = _shopriteValues(prices, lines);

  final desc = lines.where((l) {
    if (prices.contains(l)) return false;
    if (l.th < 0.6 * body || l.th > 1.8 * body) return false;
    if (_shopriteNoise.hasMatch(l.t)) return false;
    final perKg = RegExp(r'^per\s?kg$', caseSensitive: false).hasMatch(l.t);
    return perKg || (_letters(l.t) >= 3 && _mostlyUpper(l.t));
  }).toList();

  // Descriptions sit under their price, roughly centred on it.
  final byPrice = _assign<OcrLine>(desc, prices, (line, p) {
    if (line.y < p.bottom - 0.15 * p.th) return null;
    final dy = line.y - p.bottom;
    if (dy > 1.5 * p.th) return null;
    final reach = math.min(1.3 * p.th, 5 * body);
    if (line.right < p.x - reach || line.x > p.right + reach) return null;
    return _gap(line, p);
  });

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
    // Keep only the lines that run on from the price without a break, so
    // text from the next row of products is not swept in.
    final stacked = byPrice[p]!..sort((a, b) => a.y.compareTo(b.y));
    final own = <OcrLine>[];
    for (final l in stacked) {
      if (own.isNotEmpty) {
        final lowest = own.map((o) => o.bottom).reduce(math.max);
        if (l.y - lowest > 1.3 * body) break;
      }
      own.add(l);
    }
    if (own.isEmpty) continue;
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
  final saveWords = lines
      .where((l) => l.t.toUpperCase() == 'SAVE')
      .toList();

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
    // The ngwee were not read; the kwacha amount is still right.
    prices.add(_GamePrice(l, double.parse(digits), l.right, false));
  }
  if (prices.isEmpty) return const [];

  final priceLines = {for (final p in prices) p.main};
  final candidates = lines.where((l) {
    if (priceLines.contains(l)) return false;
    if (l.th < 0.72 * body || l.th > 1.4 * body) return false;
    if (_letters(l.t) < 2 && parseSize(l.t) == null) return false;
    return !RegExp(
      r'^(each|per\s?kg|save.*|was\b.*|now\b.*|t&c.*|while stocks.*|black friday.*)$',
      caseSensitive: false,
    ).hasMatch(l.t);
  }).toList()..sort((a, b) => a.y.compareTo(b.y));

  // Stack lines into left-aligned blocks.
  final blocks = <_Block>[];
  for (final l in candidates) {
    _Block? home;
    for (final b in blocks) {
      final last = b.lines.last;
      final gap = l.y - last.bottom;
      final ratio = l.th / last.th;
      if ((l.x - last.x).abs() <= 0.6 * l.th &&
          gap > -0.35 * l.th &&
          gap < 0.9 * l.th &&
          ratio > 0.72 &&
          ratio < 1.38) {
        home = b;
      }
    }
    if (home == null) {
      blocks.add(_Block(l));
    } else {
      home.lines.add(l);
    }
  }

  // Pair each price with its nearest block, closest pairs first.
  final pairs = <(double, _GamePrice, _Block)>[];
  for (final p in prices) {
    final m = p.main;
    for (final b in blocks) {
      double? cost;
      // Block to the left of the price, overlapping it vertically.
      final hGap = m.x - b.right;
      if (hGap > -0.3 * m.th &&
          hGap < 3.2 * m.th &&
          b.y < m.bottom + 0.5 * m.th &&
          b.bottom > m.y - 0.5 * m.th) {
        cost = math.max(0, hGap).toDouble();
      }
      // Block just above the price, starting at about the same left edge.
      final vGap = m.y - b.bottom;
      final shift = (b.x - m.x).abs();
      if (vGap > -0.4 * m.th && vGap < 2.2 * m.th && shift < 1.5 * m.th) {
        final c = math.max(0, vGap) + shift;
        if (cost == null || c < cost) cost = c;
      }
      if (cost == null) continue;
      // Real descriptions are neat stacks of clearly printed lines. Stray
      // words from the packaging are single lines, often poorly read.
      if (b.lines.length == 1) cost += 1.5 * m.th;
      final score =
          b.lines.map((l) => l.s).reduce((x, y) => x + y) / b.lines.length;
      cost += (1 - score) * 3 * m.th;
      pairs.add((cost, p, b));
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));

  final usedPrices = <_GamePrice>{};
  final usedBlocks = <_Block>{};
  final items = <ExtractedItem>[];
  for (final (_, p, b) in pairs) {
    if (usedPrices.contains(p) || usedBlocks.contains(b)) continue;
    usedPrices.add(p);
    usedBlocks.add(b);

    final raw = b.lines.map((l) => l.t).join(' ');
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
        confidence: p.certain ? _confidence(m, b.lines) : 0.8 * _confidence(m, b.lines),
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
  'Electronics & appliances': [
    'tv', 'television', 'fridge', 'freezer', 'phone', 'laptop', 'kettle',
    'iron', 'microwave', 'speaker', 'speakers', 'stove', 'blender', 'fan',
    'heater', 'washing machine', 'soundbar', 'tablet', 'printer',
    'headphones', 'earbuds', 'fryer', 'cooker', 'toaster', 'decoder',
    'inverter', 'solar', 'generator', 'smartphone', 'refrigerator', 'vacuum',
    'oven', 'hob', 'power bank', 'console', 'monitor', 'air conditioner',
    'clipper', 'hair cutting', 'laminator', 'laminating', 'hood', 'ryzen',
    'intel', 'smart tank', 'box set', 'chest freezer',
  ],
  'Home & outdoor': [
    'mattress', 'bed', 'chair', 'table', 'pots', 'pan', 'bicycle', 'toy',
    'toys', 'christmas', 'lights', 'duvet', 'blanket', 'pillow', 'towel',
    'luggage', 'suitcase', 'tent', 'pool', 'trampoline', 'tyre', 'drill',
    'paint', 'cutlery', 'dinner set', 'storage', 'couch', 'sofa', 'wardrobe',
    'curtain', 'ladder', 'cookware', 'comforter', 'stroller', 'scooter',
    'umbrella', 'patio', 'cot', 'bouncer', 'fry combo', 'camping',
    'dinnerware', 'casserole', 'flask', 'cooler box', 'bedding',
  ],
  'Baby & personal care': [
    'diapers', 'nappies', 'lotion', 'toothpaste', 'shampoo', 'pads', 'wipes',
    'deodorant', 'roll-on', 'roll on', 'petroleum', 'vaseline', 'colgate',
    'razor', 'sanitary', 'conditioner', 'bath', 'body', 'showergel', 'deo',
    'liners', 'hand soap', 'antiseptic', 'repellent',
  ],
  'Liquor': [
    'beer', 'wine', 'whisky', 'whiskey', 'lager', 'cider', 'vodka', 'gin',
    'brandy', 'castle', 'mosi', 'amarula', 'rum', 'liqueur', 'spritzer',
    'savanna', 'heineken', 'corona',
  ],
  'Household': [
    'washing', 'detergent', 'soap', 'tissue', 'toilet', 'bleach', 'cleaner',
    'dishwashing', 'softener', 'polish', 'insecticide', 'doom', 'candles',
    'matches', 'foil', 'refuse', 'air freshener', 'paper towel', 'scouring',
    'cleaning', 'laundry', 'pine gel', 'car care',
  ],
  'Snacks & sweets': [
    'chips', 'biscuits', 'biscuit', 'cookies', 'chocolate', 'sweets', 'curls',
    'crisps', 'wafers', 'snacks', 'snack', 'popcorn', 'slab', 'candy',
    'lollipop', 'jelly', 'marshmallows', 'eclairs', 'peanuts', 'chews',
    'shortbread', 'marie',
  ],
  'Drinks': [
    'juice', 'drink', 'drinks', 'coke', 'fanta', 'sprite', 'water', 'squash',
    'cordial', 'energy', 'cola', 'soda', 'nectar', 'mazoe', 'pepsi',
    'mirinda', 'milkshake', 'milk shake',
  ],
  'Pantry': [
    'rice', 'sugar', 'oil', 'flour', 'meal', 'beans', 'pasta', 'noodles',
    'sauce', 'salt', 'tea', 'teabags', 'coffee', 'cereal', 'oats', 'jam',
    'peanut butter', 'macaroni', 'spaghetti', 'soup', 'spice', 'spices',
    'curry', 'mayonnaise', 'ketchup', 'honey', 'bread', 'corn flakes',
    'creamer', 'soya', 'soy', 'stock', 'vinegar', 'porridge', 'gravy',
    'syrup', 'yeast', 'custard', 'mealie', 'samp', 'lentils', 'tomato',
    'cocoa', 'mchuzi', 'ricoffy', 'paste',
  ],
  'Meat & fish': [
    'chicken', 'beef', 'mince', 'sausage', 'wors', 'pork', 'steak', 'fish',
    'polony', 'bacon', 'vienna', 'burger', 'drumstick', 'tuna', 'pilchard',
    'pilchards', 'kapenta', 'chops', 'goat', 'lamb', 'hungarian', 'russian',
    'corned', 'bream', 'gizzard', 'liver', 'hake',
  ],
  'Dairy & eggs': [
    'milk', 'cheese', 'yoghurt', 'yogurt', 'butter', 'margarine', 'spread',
    'eggs', 'cream', 'maas', 'lacto',
  ],
  'Fruit & veg': [
    'apples', 'onions', 'potatoes', 'tomatoes', 'bananas', 'oranges',
    'cabbage', 'carrots', 'grapes', 'lemons', 'avocado', 'peppers',
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
