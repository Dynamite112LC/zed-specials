// The price history store: what every product cost in every leaflet the
// feed builder has seen. Leaflets disappear from the shops' sites when they
// end, so this file is the only record of old prices.
import 'dart:convert';
import 'dart:io';

import 'package:zed_specials/src/models.dart';

import 'matching.dart';

/// Short stable name for a catalogue, used in file names and as its key in
/// the history.
String shortId(String id) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(id)) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class Leaflet {
  Leaflet({
    required this.id,
    required this.retailerId,
    required this.title,
    required this.from,
    required this.firstSeen,
    this.to,
  });

  final String id;
  final String retailerId;
  final String title;
  final DateTime from;
  final DateTime? to;
  final DateTime firstSeen;

  Map<String, dynamic> toJson() => {
    'id': id,
    'retailer': retailerId,
    'title': title,
    'from': _day(from),
    if (to != null) 'to': _day(to!),
    'firstSeen': _day(firstSeen),
  };

  factory Leaflet.fromJson(Map<String, dynamic> j) => Leaflet(
    id: j['id'] as String,
    retailerId: j['retailer'] as String,
    title: j['title'] as String,
    from: DateTime.parse(j['from'] as String),
    to: j['to'] == null ? null : DateTime.parse(j['to'] as String),
    firstSeen: DateTime.parse(j['firstSeen'] as String),
  );
}

/// One product at one shop, with its price in each leaflet it appeared in.
class Product {
  Product({
    required this.retailerId,
    required this.name,
    required this.perKg,
    required this.reference,
    this.sizeQty,
    this.sizeUnit,
    Map<String, double>? prices,
  }) : prices = prices ?? {};

  final String retailerId;
  final String name;
  final bool perKg;
  final double? sizeQty;
  final String? sizeUnit;

  /// Leaflet key to the price read there.
  final Map<String, double> prices;

  /// The latest known price, for telling a real match from a misreading.
  double reference;

  /// Stands in for the product when asking "is this the same thing?".
  DealItem get asItem => DealItem(
    id: '',
    catalogueId: '',
    retailerId: retailerId,
    page: 0,
    name: name,
    price: reference,
    perKg: perKg,
    sizeQty: sizeQty,
    sizeUnit: sizeUnit,
  );

  String get identity => _identity(name, perKg, sizeQty, sizeUnit);

  Map<String, dynamic> toJson() => {
    'retailer': retailerId,
    'name': name,
    if (perKg) 'perKg': true,
    if (sizeQty != null) 'sizeQty': sizeQty,
    if (sizeUnit != null) 'sizeUnit': sizeUnit,
    'prices': prices,
  };

  factory Product.fromJson(Map<String, dynamic> j) {
    final prices = {
      for (final e in (j['prices'] as Map<String, dynamic>).entries)
        e.key: (e.value as num).toDouble(),
    };
    return Product(
      retailerId: j['retailer'] as String,
      name: j['name'] as String,
      perKg: j['perKg'] as bool? ?? false,
      sizeQty: (j['sizeQty'] as num?)?.toDouble(),
      sizeUnit: j['sizeUnit'] as String?,
      prices: prices,
      reference: prices.isEmpty ? 0 : prices.values.last,
    );
  }
}

String _identity(String name, bool perKg, double? qty, String? unit) {
  final words = productWords(name).toList()..sort();
  return '${words.join(' ')}|$perKg|$qty|$unit';
}

class PriceHistory {
  PriceHistory({Map<String, Leaflet>? leaflets, List<Product>? products})
    : leaflets = leaflets ?? {},
      products = products ?? [];

  /// By [shortId] of the catalogue id.
  final Map<String, Leaflet> leaflets;
  final List<Product> products;

  /// Leaflets older than this are forgotten.
  static const keep = Duration(days: 550);

  /// Reads the store. A missing file starts a new history; a damaged one
  /// throws, because carrying on would overwrite the record with nothing.
  static PriceHistory load(File file) {
    if (!file.existsSync()) return PriceHistory();
    final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return PriceHistory(
      leaflets: {
        for (final e in (j['leaflets'] as Map<String, dynamic>).entries)
          e.key: Leaflet.fromJson(e.value as Map<String, dynamic>),
      },
      products: [
        for (final p in j['products'] as List)
          Product.fromJson(p as Map<String, dynamic>),
      ],
    );
  }

  /// One leaflet and one product per line, so day-to-day changes are small
  /// and readable in version control.
  void save(File file) {
    final b = StringBuffer('{\n "version": 1,\n "leaflets": {\n');
    final keys = leaflets.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      b.write('  ${jsonEncode(keys[i])}: ${jsonEncode(leaflets[keys[i]])}');
      b.write(i == keys.length - 1 ? '\n' : ',\n');
    }
    b.write(' },\n "products": [\n');
    for (var i = 0; i < products.length; i++) {
      b.write('  ${jsonEncode(products[i])}');
      b.write(i == products.length - 1 ? '\n' : ',\n');
    }
    b.write(' ]\n}\n');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(b.toString());
  }

  DateTime? firstSeen(String catalogueId) =>
      leaflets[shortId(catalogueId)]?.firstSeen;

  /// Records today's readings and returns the items with their earlier
  /// prices attached.
  ///
  /// The readings of a leaflet that is still published replace whatever was
  /// recorded for it before, so a price that was misread and later fixed
  /// does not linger in the history.
  List<DealItem> record(
    List<Catalogue> catalogues,
    List<DealItem> items,
    DateTime today,
  ) {
    for (final p in products) {
      p.reference = _latestPrice(p);
    }

    final live = <String>{};
    for (final c in catalogues) {
      final key = shortId(c.id);
      live.add(key);
      final old = leaflets[key];
      leaflets[key] = Leaflet(
        id: c.id,
        retailerId: c.retailerId,
        title: c.title,
        from: c.validFrom ?? old?.from ?? c.firstSeen ?? today,
        to: c.validTo,
        firstSeen: old?.firstSeen ?? c.firstSeen ?? today,
      );
    }

    // Forget leaflets that ended long ago.
    final cutoff = today.subtract(keep);
    leaflets.removeWhere(
      (key, l) => !live.contains(key) && (l.to ?? l.from).isBefore(cutoff),
    );

    for (final p in products) {
      p.prices.removeWhere(
        (key, _) => live.contains(key) || !leaflets.containsKey(key),
      );
    }

    final byShop = <String, List<Product>>{};
    final byIdentity = <String, List<Product>>{};
    for (final p in products) {
      byShop.putIfAbsent(p.retailerId, () => []).add(p);
      byIdentity.putIfAbsent('${p.retailerId}|${p.identity}', () => []).add(p);
    }

    bool plausiblePrice(double a, double b) {
      final lo = a < b ? a : b, hi = a < b ? b : a;
      return lo > 0 && hi / lo <= 3;
    }

    final own = <String, Product>{};
    for (final item in items) {
      final key = shortId(item.catalogueId);
      final identity =
          '${item.retailerId}|'
          '${_identity(item.name, item.perKg, item.sizeQty, item.sizeUnit)}';
      Product? match;
      // The same wording and pack size as before is the same product.
      for (final p in byIdentity[identity] ?? const <Product>[]) {
        if (p.prices.containsKey(key)) continue;
        if (!plausiblePrice(p.reference, item.price)) continue;
        match = p;
        break;
      }
      // Otherwise allow for the leaflet wording it a little differently.
      if (match == null) {
        for (final p in byShop[item.retailerId] ?? const <Product>[]) {
          if (p.prices.containsKey(key)) continue;
          if (sameProduct(item, p.asItem)) {
            match = p;
            break;
          }
        }
      }
      if (match == null) {
        match = Product(
          retailerId: item.retailerId,
          name: item.name,
          perKg: item.perKg,
          sizeQty: item.sizeQty,
          sizeUnit: item.sizeUnit,
          reference: item.price,
        );
        products.add(match);
        byShop.putIfAbsent(item.retailerId, () => []).add(match);
        byIdentity.putIfAbsent(identity, () => []).add(match);
      }
      match.prices[key] = item.price;
      own[item.id] = match;
    }
    products.removeWhere((p) => p.prices.isEmpty);
    for (final p in products) {
      p.reference = _latestPrice(p);
    }

    // Earlier prices: the product's own, and the same product at the other
    // shops. Leaflets still published are left out; the app already shows
    // those side by side.
    final past = products
        .where((p) => p.prices.keys.any((k) => !live.contains(k)))
        .toList();
    return [
      for (final item in items)
        item.copyWith(history: _earlier(item, own[item.id]!, past, live)),
    ];
  }

  double _latestPrice(Product p) {
    DateTime? latest;
    var price = p.reference;
    p.prices.forEach((key, value) {
      final from = leaflets[key]?.from;
      if (from == null) return;
      if (latest == null || from.isAfter(latest!)) {
        latest = from;
        price = value;
      }
    });
    return price;
  }

  List<PricePoint> _earlier(
    DealItem item,
    Product mine,
    List<Product> past,
    Set<String> live,
  ) {
    final points = <PricePoint>[];
    final seen = <String>{};
    void take(Product p) {
      p.prices.forEach((key, price) {
        if (live.contains(key)) return;
        final l = leaflets[key]!;
        if (!seen.add('${p.retailerId}|${_day(l.from)}|$price')) return;
        points.add(
          PricePoint(
            retailerId: p.retailerId,
            from: l.from,
            to: l.to,
            price: price,
          ),
        );
      });
    }

    take(mine);
    for (final p in past) {
      if (p.retailerId == item.retailerId) continue;
      if (sameProduct(item, p.asItem)) take(p);
    }
    points.sort((a, b) => a.from.compareTo(b.from));
    return points.length > 12 ? points.sublist(points.length - 12) : points;
  }

  /// Products that have a price in more than one leaflet.
  int get tracked => products.where((p) => p.prices.length > 1).length;
}
