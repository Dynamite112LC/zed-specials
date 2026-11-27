// Decides which items from different leaflets are the same product, so the
// app can put their prices side by side.
import 'package:zed_specials/src/models.dart';

const _noise = {
  'each', 'assorted', 'all', 'variants', 'variant', 'per', 'pack', 'or',
  'and', 'with', 'the', 'in', 'of', 'selected', 'excl', 'incl', 'only',
  'new', 'for', 'kg', 'ml', 'ltr', 'litre', 'litres', 'pnp', 'range',
  'flavours', 'flavour',
};

/// The words that identify a product, without sizes or filler.
Set<String> productWords(String name) {
  final cleaned = name
      .toLowerCase()
      .replaceAll(RegExp(r"['’]s\b"), '')
      .replaceAll(RegExp(r'\d+(?:[.,]\d+)?\s?(?:kg|g|ml|l|ltr|litres?|s|pack|x)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  final words = <String>{};
  for (var w in cleaned.split(' ')) {
    if (w.length < 2 || _noise.contains(w)) continue;
    if (RegExp(r'^\d+$').hasMatch(w)) continue;
    // Crude singular: "portions" and "portion" should match.
    if (w.length > 4 && w.endsWith('s') && !w.endsWith('ss')) {
      w = w.substring(0, w.length - 1);
    }
    words.add(w);
  }
  return words;
}

String? _leadWord(String name) {
  for (final raw in name.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    var w = raw;
    if (w.length < 2 || _noise.contains(w)) continue;
    if (w.length > 4 && w.endsWith('s') && !w.endsWith('ss')) {
      w = w.substring(0, w.length - 1);
    }
    return w;
  }
  return null;
}

bool _sizeKnown(DealItem i) => i.sizeQty != null && i.sizeUnit != null;

bool _sameSize(DealItem a, DealItem b) {
  if (a.sizeUnit != b.sizeUnit) return false;
  final x = a.sizeQty!, y = b.sizeQty!;
  return (x - y).abs() <= 0.03 * (x > y ? x : y);
}

/// True when [a] and [b] look like the same product in the same pack size.
bool sameProduct(DealItem a, DealItem b) {
  if (a.perKg != b.perKg) return false;
  final wa = productWords(a.name), wb = productWords(b.name);
  if (wa.isEmpty || wb.isEmpty) return false;

  // The brand leads the name. One shop may print a longer form of it
  // ("Robertsons Rajah" against "Rajah"), so either lead word will do.
  final leadA = _leadWord(a.name), leadB = _leadWord(b.name);
  if (leadA == null || leadB == null) return false;
  if (!wb.contains(leadA) && !wa.contains(leadB)) return false;

  // The same pack rarely costs several times more at another shop; a gap
  // that wide usually means one of the prices was misread.
  final lo = a.price < b.price ? a.price : b.price;
  final hi = a.price < b.price ? b.price : a.price;
  if (lo <= 0 || hi / lo > 2.5) return false;

  final shared = wa.intersection(wb).length;
  final jaccard = shared / wa.union(wb).length;

  final bothSized = _sizeKnown(a) && _sizeKnown(b);
  if (bothSized) {
    if (!_sameSize(a, b)) return false;
    return shared >= 2 && jaccard >= 0.6;
  }
  if (a.perKg) {
    // Fresh meat and produce sold by weight: names are short.
    return jaccard >= 0.6 && shared >= 2;
  }
  // A missing size makes a match much less certain: ask for more.
  return shared >= 3 && jaccard >= 0.75;
}

/// Gives items that are the same product a shared group id.
List<DealItem> groupSimilar(List<DealItem> items) {
  final clusters = <List<int>>[];
  for (var i = 0; i < items.length; i++) {
    var placed = false;
    for (final cluster in clusters) {
      if (sameProduct(items[cluster.first], items[i])) {
        cluster.add(i);
        placed = true;
        break;
      }
    }
    if (!placed) clusters.add([i]);
  }

  final out = [...items];
  var n = 0;
  for (final cluster in clusters) {
    if (cluster.length < 2) continue;
    n++;
    for (final i in cluster) {
      out[i] = out[i].copyWith(groupId: 'g$n');
    }
  }
  return out;
}
