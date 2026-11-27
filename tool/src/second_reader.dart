// Puts two readings of one leaflet page together.
//
// The first reading is the shop's own reader in extract.dart: it knows where
// everything is on the page and spells words well, but it misses an item
// whose price or description it could not make out, and it garbles pack
// sizes ("2L" read as "2", "36cm" as "3b").
//
// The second reading comes from a vision model that looks at the whole page
// (tool/second_reader.py). It gives names and prices but no positions; it
// rarely misses an item and reads sizes well, but it misspells words now and
// then and sometimes drops the decimal point of a price.
//
// So: a price both readers give is marked as agreed; a price they differ on
// keeps the first reading and carries the other one for a person to check;
// sizes the first reader garbled are taken from the second; and an item only
// the second reader names is added when the page's own text shows its price
// and its words in one place.
import 'dart:math' as math;

import 'extract.dart';

class SecondItem {
  const SecondItem(this.name, this.price, {this.perKg = false});
  final String name;
  final double price;

  /// The second reader gave this as a price per kilogram.
  final bool perKg;
}

/// The items in a saved second reading. Null when the file records a failed
/// attempt, or is not a reading at all.
List<SecondItem>? parseSecondReading(Object? json) {
  if (json is! Map || json['items'] is! List) return null;
  final out = <SecondItem>[];
  for (final j in json['items'] as List) {
    if (j is! Map) continue;
    final name = j['name'];
    final price = j['price'];
    if (name is! String || price is! num) continue;
    if (price < 1 || price > 250000) continue;
    // "6 x 330ml" is one size, like "6x330ml".
    final cleaned = cleanName(
      name.replaceAllMapped(
        RegExp(r'(\d)\s?[xX×]\s?(\d)'),
        (m) => '${m[1]}x${m[2]}',
      ),
    );
    if (RegExp(r'[A-Za-z]{3,}').allMatches(cleaned).isEmpty) continue;
    if (cleaned.length > 110) continue;
    out.add(SecondItem(cleaned, price.toDouble(), perKg: saysPerKg(name)));
  }
  return out;
}

class CombinedReading {
  CombinedReading(this.items);
  final List<ExtractedItem> items;

  /// Prices both readers gave.
  int agreed = 0;

  /// Prices the readers differ on.
  int doubted = 0;

  /// Names repaired from the second reading.
  int renamed = 0;

  /// Items only the second reader found, confirmed by the page's text.
  int added = 0;

  /// What a person checking the run would want to know.
  final List<String> notes = [];
}

// ------------------------------------------------------------------ words

const _filler = {
  'assorted',
  'each',
  'per',
  'set',
  'pack',
  'all',
  'variants',
  'and',
  'for',
  'the',
  'with',
};

String _key(String token) =>
    token.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Edit distance, giving up (returning [limit] + 1) once it passes [limit].
int _distance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, i);
    var best = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      row[j] = math.min(
        math.min(prev[j] + 1, row[j - 1] + 1),
        prev[j - 1] + cost,
      );
      best = math.min(best, row[j]);
    }
    if (best > limit) return limit + 1;
    prev = row;
  }
  return prev[b.length];
}

/// The same word, allowing for one reader having misread a letter or two
/// of a long word ("Frition" for "Friction").
bool _sameWord(String a, String b) {
  if (a == b) return a.isNotEmpty;
  if (RegExp(r'\d').hasMatch(a) || RegExp(r'\d').hasMatch(b)) return false;
  final shorter = math.min(a.length, b.length);
  if (shorter < 5) return false;
  return _distance(a, b, shorter >= 8 ? 2 : 1) <= (shorter >= 8 ? 2 : 1);
}

List<String> _words(String name) => [
  for (final t in name.split(RegExp(r'[\s/]+')))
    if (_key(t).length >= 2 && !_filler.contains(_key(t))) _key(t),
];

/// How much of the shorter name is found in the other, 0..1.
double _similarity(String a, String b) {
  final wa = _words(a), wb = _words(b);
  if (wa.isEmpty || wb.isEmpty) return 0;
  final short = wa.length <= wb.length ? wa : wb;
  final long = identical(short, wa) ? wb : wa;
  var hits = 0;
  for (final w in short) {
    if (long.any((o) => _sameWord(w, o))) hits++;
  }
  return hits / short.length;
}

/// A size or measure: "2L", "36cm", "1.5kg", "4-piece", "43"".
final _measure = RegExp(
  r'''^\(?\d+(?:[.,]\d+)?(?:x\d+(?:[.,]\d+)?)?(?:ml|cl|l|lt|ltr|kg|g|mg|cm|mm|m|w|kw|v|gb|tb|mah|pk|"|”|''|-piece|-pack|-ply)\)?$''',
  caseSensitive: false,
);

bool _hasMeasure(List<String> tokens) => tokens.any(_measure.hasMatch);

/// Whether [token] could be the first reader's garbling of [size]: it starts
/// with the same number, or is a letter or two off.
bool _garbled(String token, String size) {
  if (!_hasDigit(token) || _measure.hasMatch(token)) return false;
  final mine = RegExp(r'^\(?(\d+)').firstMatch(token)?.group(1);
  final theirs = RegExp(r'^\(?(\d+)').firstMatch(size)?.group(1);
  if (mine != null && theirs != null && theirs.startsWith(mine)) return true;
  return _distance(token.toLowerCase(), size.toLowerCase(), 2) <= 2;
}

bool _hasDigit(String t) => RegExp(r'\d').hasMatch(t);

/// [first] with the sizes it garbled or left out taken from [second].
///
/// Words are left as the first reader spelled them: where the two differ on
/// a word, the first reader is nearly always the one that is right.
String mergeNames(String first, String second) {
  final a = first.split(' ').where((t) => t.isNotEmpty).toList();
  final b = second.split(' ').where((t) => t.isNotEmpty).toList();
  if (a.isEmpty || b.isEmpty) return first;
  bool same(int i, int j) => _sameWord(_key(a[i]), _key(b[j]));

  // Longest run of words the two names share, in order.
  final lcs = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = same(i, j)
          ? lcs[i + 1][j + 1] + 1
          : math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  // Names that share nothing are not two readings of the same words.
  if (lcs[0][0] == 0) return first;

  final out = <String>[];
  void between(List<String> mine, List<String> theirs) {
    if (mine.isEmpty) {
      // A size or model number only the second reader saw. Plain words
      // only it saw are left out: they may not be on the page.
      out.addAll(
        theirs.where(
          (t) => _hasDigit(t) && RegExp(r'''[A-Za-z"”]''').hasMatch(t),
        ),
      );
      return;
    }
    final sizes = theirs.where(_measure.hasMatch).toList();
    final sized = _hasMeasure(mine) || parseSize(mine.join(' ')) != null;
    if (sizes.isEmpty || sized) {
      out.addAll(mine);
      return;
    }
    // The size, garbled: "2" for "2L", "3b" for "36cm", "s00ml" for "500ml".
    if (sizes.length == 1) {
      final at = mine.indexWhere((t) => _garbled(t, sizes.single));
      if (at >= 0) {
        out
          ..addAll(mine.sublist(0, at))
          ..add(sizes.single)
          ..addAll(mine.sublist(at + 1));
        return;
      }
    }
    // "Alss AA" for "ALL VARIANTS 2L": a word or two that are no words,
    // where the second reader has only the stock phrase and a size.
    if (mine.length <= 2 &&
        !mine.any(_hasDigit) &&
        theirs.any((t) => _key(t) == 'assorted') &&
        theirs.every((t) => _measure.hasMatch(t) || _key(t) == 'assorted')) {
      out.addAll(theirs);
      return;
    }
    // "SAUUEOml" for "Sauce 700ml": a word and its size run together.
    if (mine.length == 1 && sizes.length == 1) {
      final unit = RegExp(r'[A-Za-z]+$').firstMatch(sizes.single)?.group(0);
      if (unit != null &&
          mine.single.length > unit.length + 2 &&
          mine.single.toLowerCase().endsWith(unit.toLowerCase())) {
        out.addAll(theirs);
        return;
      }
    }
    out
      ..addAll(mine)
      ..addAll(sizes);
  }

  var i = 0, j = 0;
  var mine = <String>[], theirs = <String>[];
  while (i < a.length && j < b.length) {
    if (same(i, j)) {
      between(mine, theirs);
      mine = [];
      theirs = [];
      out.add(a[i]);
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      mine.add(a[i++]);
    } else {
      theirs.add(b[j++]);
    }
  }
  mine.addAll(a.sublist(i));
  theirs.addAll(b.sublist(j));
  between(mine, theirs);
  final merged = out.join(' ');
  return merged.isEmpty ? first : merged;
}

// ----------------------------------------------------------------- prices

bool _samePrice(double a, double b) => (a - b).abs() < 0.005;

final _multiBuyNote = RegExp(r'\((\d+) for K(\d+(?:\.\d+)?)\)');

/// How the second reader's price sits with the first reader's item.
///
/// [agreed]: the same price. [price]: the price to show, when it is not
/// the first reader's. [other]: the reading that lost out, kept for a
/// person to check against the leaflet. None of the three: nothing to
/// conclude, and the first reading stands as it is.
///
/// What the second reader gets wrong is known from checking its readings
/// against the leaflets: it runs raised ngwee into the kwacha (2699 for
/// 26.99), loses a digit doing so (2699 for 269.99), or leaves the ngwee
/// out (399 for 399.99). It loses digits; it does not make them up. So
/// ngwee it does report, where the first reader has none or had to assume
/// them, are believed, and ngwee it leaves out say nothing.
///
/// [wholeKwachaPage]: both readers find whole-kwacha prices all over this
/// page, so ngwee on one item are the odd ones out.
({bool agreed, double? other, double? price}) _compare(
  ExtractedItem mine,
  double theirs, {
  bool wholeKwachaPage = false,
}) {
  const yes = (agreed: true, other: null, price: null);
  const unsure = (agreed: false, other: null, price: null);
  final first = mine.price;
  if (_samePrice(first, theirs)) return yes;
  // The loyalty-card price printed under the usual one is not a second
  // opinion on the usual one.
  final card = mine.cardPrice;
  if (card != null &&
      (_samePrice(card, theirs) || _samePrice(card * 100, theirs))) {
    return unsure;
  }

  // "2 for K70" is shown as K35 each; the second reader gives the K70.
  final deal = _multiBuyNote.firstMatch(mine.name);
  if (deal != null) {
    final total = double.parse(deal.group(2)!);
    if (_samePrice(total, theirs)) return yes;
    if (_samePrice(total * 100, theirs)) return unsure;
    return (agreed: false, other: theirs, price: null);
  }

  // Raised ngwee run into the kwacha: 2699 for 26.99, 1799 for 17.99.
  var said = theirs;
  final whole = theirs == theirs.roundToDouble();
  if (whole && theirs >= 100 && (theirs ~/ 100) == first.floor()) {
    said = theirs / 100;
    if (_samePrice(said, first)) return unsure;
  }

  if (said.floor() == first.floor()) {
    // The kwacha agree; the ngwee do not.
    final mineNgwee = (first * 100).round() % 100;
    final saidNgwee = (said * 100).round() % 100;
    if (saidNgwee == 0) {
      // Left out, most likely. Only ngwee the first reader could not read
      // and assumed, on a page priced in whole kwacha, give way.
      if (mine.assumedNgwee && wholeKwachaPage) {
        return (agreed: true, other: null, price: said);
      }
      return unsure;
    }
    final believed =
        !wholeKwachaPage &&
        (mineNgwee == 0 || mine.assumedNgwee || saidNgwee == 99);
    return believed
        ? (agreed: false, other: first, price: said)
        : (agreed: false, other: said, price: null);
  }

  // The same digits with one lost on the way: 2699 for 269.99.
  if (whole && theirs > 5 * first) {
    final a = (first * 100).round().toString();
    final b = theirs.round().toString();
    if (a.startsWith(b) || b.startsWith(a)) return unsure;
  }
  return (agreed: false, other: theirs, price: null);
}

// ---------------------------------------------------------------- combine

/// [page] is the page's own text and colour reading, used to confirm an
/// item only the second reader named. Without it nothing is added.
CombinedReading combineReadings(
  List<ExtractedItem> first,
  List<SecondItem> second, {
  OcrPage? page,
}) {
  final matchOf = <int, int>{}; // first index -> second index
  final taken = <int>{}; // second indexes

  void pair(bool Function(int c, int v) allowed, double least) {
    final pairs = <(double, int, int)>[];
    for (var c = 0; c < first.length; c++) {
      if (matchOf.containsKey(c)) continue;
      for (var v = 0; v < second.length; v++) {
        if (taken.contains(v) || !allowed(c, v)) continue;
        final s = _similarity(first[c].name, second[v].name);
        if (s >= least) pairs.add((s, c, v));
      }
    }
    pairs.sort((x, y) => y.$1.compareTo(x.$1));
    for (final (_, c, v) in pairs) {
      if (matchOf.containsKey(c) || taken.contains(v)) continue;
      matchOf[c] = v;
      taken.add(v);
    }
  }

  // Whether this page is priced in whole kwacha, as far as both readers
  // can tell (leaving out ngwee the first reader only assumed).
  final read = first.where((i) => !i.assumedNgwee).toList();
  bool round(double p) => p == p.roundToDouble();
  final wholeKwachaPage =
      read.length >= 3 &&
      read.where((i) => round(i.price)).length >= 0.8 * read.length &&
      second.where((i) => round(i.price)).length >= 0.8 * second.length;
  ({bool agreed, double? other, double? price}) compare(int c, int v) =>
      _compare(first[c], second[v].price, wholeKwachaPage: wholeKwachaPage);

  // Prices that fit and names that overlap: the same item, read twice.
  pair((c, v) => compare(c, v).other == null, 0.34);
  // Clearly the same name with another price: a disagreement.
  pair((c, v) => true, 0.6);

  final out = CombinedReading([]);
  for (var c = 0; c < first.length; c++) {
    final mine = first[c];
    final v = matchOf[c];
    if (v == null) {
      out.items.add(mine);
      continue;
    }
    final theirs = second[v];
    // A multi-buy's name says what the deal is; the second reader words
    // deals its own way ("2x125g"), so the name is left as it is.
    final name = _multiBuyNote.hasMatch(mine.name)
        ? mine.name
        : mergeNames(mine.name, theirs.name);
    final renamed = name != mine.name;
    // A repaired name may now show the size the first reader lost.
    final size = renamed ? parseSize(name) : null;
    if (renamed) out.renamed++;
    final verdict = compare(c, v);
    if (verdict.agreed) out.agreed++;
    if (verdict.other != null) out.doubted++;
    if (verdict.other != null || verdict.price != null) {
      final shown = verdict.price ?? mine.price;
      out.notes.add(
        '"${mine.name}": first reader K${mine.price.toStringAsFixed(2)}, '
        'second reader K${theirs.price.toStringAsFixed(2)}; '
        'shown K${shown.toStringAsFixed(2)}'
        '${verdict.other == null ? '' : ', to be checked'}',
      );
    }
    out.items.add(
      mine.copyWith(
        name: name,
        price: verdict.price,
        firstName: renamed ? mine.name : null,
        sizeQty: size?.$1,
        sizeUnit: size?.$2,
        agreed: verdict.agreed,
        otherPrice: verdict.other,
      ),
    );
  }

  // Several products the second reader gives one price that the first
  // reader has nowhere: a combo ("all four for K299") listed piece by
  // piece. No single one of them costs that.
  final loose = <int, int>{};
  for (var v = 0; v < second.length; v++) {
    if (taken.contains(v)) continue;
    final cents = (second[v].price * 100).round();
    loose[cents] = (loose[cents] ?? 0) + 1;
  }

  for (var v = 0; v < second.length; v++) {
    if (taken.contains(v)) continue;
    final shared = loose[(second[v].price * 100).round()]! > 1;
    final found = page == null || shared
        ? null
        : _confirm(second[v], page, out.items);
    if (found == null) {
      out.notes.add(
        'only the second reader: K${second[v].price.toStringAsFixed(2)} '
        '"${second[v].name}" (left out)',
      );
    } else {
      out.items.add(found);
      out.added++;
    }
  }
  return out;
}

/// Looks on the page for the price and the words of an item only the second
/// reader named. Both have to be there, close together, and not already
/// belong to another item.
ExtractedItem? _confirm(
  SecondItem item,
  OcrPage page,
  List<ExtractedItem> have,
) {
  final kwacha = item.price.floor();
  final ngwee = ((item.price - kwacha) * 100).round();
  final two = ngwee.toString().padLeft(2, '0');

  // Places where this price is printed. The second reader may have run
  // raised ngwee into the kwacha (2699 for 26.99), so the place has to
  // settle where the point goes too.
  //
  // It also leaves ngwee out (16 for 16.99). So a whole-kwacha price is
  // only taken from it where the colour reader saw no raised digits, or
  // on a page that is priced in whole kwacha throughout.
  final wholeKwachaPage =
      have.length >= 3 &&
      have.where((i) => i.price == i.price.roundToDouble()).length >=
          0.8 * have.length;
  final spots = <OcrLine>[];
  for (final f in page.flashes) {
    // The colour reader tells full-size digits from raised ones. Raised
    // glyphs it could not read may be ngwee or a dash after whole kwacha.
    if (int.tryParse(f.kwacha) != kwacha) continue;
    if (f.raised == 0 && ngwee > 0) continue;
    if (f.raised > 0 && ngwee == 0 && !wholeKwachaPage) continue;
    spots.add(OcrLine('K${f.kwacha}', f.x, f.y, f.w, f.h, f.th, f.ks));
  }
  for (final l in page.lines) {
    if (l.s < 0.5 || !RegExp(r'^[Kk]?\s?\d[\d ,.]*$').hasMatch(l.t)) continue;
    final digits = l.t.replaceAll(RegExp(r'\D'), '');
    final fits = ngwee > 0
        ? digits == '$kwacha' || digits == '$kwacha$two'
        : digits == '$kwacha' && wholeKwachaPage;
    if (fits) spots.add(l);
  }
  bool overlaps(OcrLine a, OcrLine b) =>
      a.x < b.right && b.x < a.right && a.y < b.bottom && b.y < a.bottom;
  final usedPrices = [
    for (final i in have)
      if (i.parts.isNotEmpty) i.parts.first,
  ];
  final usedLines = {for (final i in have) ...i.parts.skip(1)};
  spots.removeWhere((s) => usedPrices.any((u) => overlaps(s, u)));
  if (spots.isEmpty) return null;

  final wanted = {
    for (final w in _words(item.name))
      if (w.length >= 4 && !_hasDigit(w)) w,
  };
  if (wanted.isEmpty) return null;

  OcrLine? bestSpot;
  var bestLines = <OcrLine>[];
  var bestHits = 0;
  for (final s in spots) {
    final reachX = math.max(0.16 * page.width, 1.5 * s.w);
    final reachY = math.max(0.12 * page.height, 2.5 * s.h);
    final lines = <OcrLine>[];
    final hits = <String>{};
    for (final l in page.lines) {
      if (l.s < 0.5 || usedLines.contains(l) || identical(l, s)) continue;
      if ((l.cx - s.cx).abs() > reachX || (l.cy - s.cy).abs() > reachY) {
        continue;
      }
      final here = {
        for (final w in _words(l.t))
          for (final want in wanted)
            if (_sameWord(w, want)) want,
      };
      if (here.isEmpty) continue;
      lines.add(l);
      hits.addAll(here);
    }
    if (hits.length > bestHits) {
      bestSpot = s;
      bestLines = lines;
      bestHits = hits.length;
    }
  }
  if (bestSpot == null) return null;
  if (bestHits < 2 && bestHits * 2 < wanted.length) return null;

  // Where the page's own text spells a word differently, it is right.
  final seen = [for (final l in bestLines) ...l.t.split(RegExp(r'[\s/]+'))];
  final name = cleanName(
    item.name
        .split(' ')
        .map((t) {
          final k = _key(t);
          if (k.length < 5 || _hasDigit(k)) return t;
          for (final o in seen) {
            final ko = _key(o);
            if (ko != k && _sameWord(k, ko)) {
              return o.replaceAll(RegExp(r'''^[^A-Za-z]+|[^A-Za-z]+$'''), '');
            }
          }
          return t;
        })
        .join(' '),
  );

  var x0 = bestSpot.x, y0 = bestSpot.y;
  var x1 = bestSpot.right, y1 = bestSpot.bottom;
  for (final l in bestLines) {
    x0 = math.min(x0, l.x);
    y0 = math.min(y0, l.y);
    x1 = math.max(x1, l.right);
    y1 = math.max(y1, l.bottom);
  }
  // Room for the product's picture, which sits beside or above its price.
  final least = 0.2 * page.width;
  final growX = math.max(0.0, least - (x1 - x0)) / 2;
  final growY = math.max(0.0, least - (y1 - y0)) / 2;
  final left = math.max(0.0, x0 - growX);
  final top = math.max(0.0, y0 - growY);
  final right = math.min(page.width.toDouble(), x1 + growX);
  final bottom = math.min(page.height.toDouble(), y1 + growY);
  // "per kg" printed with the item: beside its price or under its name.
  // The second reader mostly leaves it out, so the page's text decides.
  final reach = 1.6 * bestSpot.th;
  final perKg =
      item.perKg ||
      page.lines.any(
        (l) =>
            l.s >= 0.5 &&
            !usedLines.contains(l) &&
            saysPerKg(l.t) &&
            l.cx > x0 - reach &&
            l.cx < x1 + reach &&
            l.cy > y0 - reach &&
            l.cy < y1 + reach,
      );
  final size = perKg ? null : parseSize(name);
  return ExtractedItem(
    name: name,
    price: item.price,
    perKg: perKg,
    sizeQty: size?.$1,
    sizeUnit: size?.$2,
    // Two readers, but the first only in pieces.
    confidence: 0.8,
    agreed: true,
    parts: [bestSpot, ...bestLines],
    crop: CropBox(
      left.round(),
      top.round(),
      math.max(2, (right - left).round()),
      math.max(2, (bottom - top).round()),
    ),
  );
}
