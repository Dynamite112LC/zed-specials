// Data model shared by the app and the feed builder in tool/.
// Pure Dart: nothing here may import Flutter.

class Retailer {
  const Retailer({
    required this.id,
    required this.name,
    required this.color,
    required this.website,
  });

  final String id;
  final String name;

  /// Brand colour as 0xRRGGBB.
  final int color;
  final String website;

  static const shoprite = Retailer(
    id: 'shoprite',
    name: 'Shoprite',
    color: 0xD9121F,
    website: 'https://www.shoprite.co.zm/specials.html',
  );
  static const picknpay = Retailer(
    id: 'picknpay',
    name: 'Pick n Pay',
    color: 0x0B4F8A,
    website: 'https://www.picknpayzambia.com/specials/',
  );
  static const game = Retailer(
    id: 'game',
    name: 'Game',
    color: 0xE5007D,
    website: 'http://www.game.co.zm/promotions/promotions',
  );

  static const all = [shoprite, picknpay, game];

  static Retailer byId(String id) =>
      all.firstWhere((r) => r.id == id, orElse: () => shoprite);
}

class CataloguePage {
  const CataloguePage({required this.image, this.width, this.height});

  /// Absolute URL, or a path relative to the feed (bundled asset or hosted).
  final String image;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() => {
    'image': image,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  };

  factory CataloguePage.fromJson(Map<String, dynamic> j) => CataloguePage(
    image: j['image'] as String,
    width: j['width'] as int?,
    height: j['height'] as int?,
  );
}

class Catalogue {
  const Catalogue({
    required this.id,
    required this.retailerId,
    required this.title,
    required this.sourceUrl,
    required this.pages,
    this.cover,
    this.validFrom,
    this.validTo,
    this.stores,
    this.firstSeen,
    this.areas = const [],
  });

  final String id;
  final String retailerId;
  final String title;
  final String sourceUrl;
  final String? cover;
  final DateTime? validFrom;
  final DateTime? validTo;

  /// Which branches the catalogue applies to, as the retailer words it.
  final String? stores;
  final DateTime? firstSeen;
  final List<CataloguePage> pages;

  /// For a shop whose leaflets differ by area, the areas this one was
  /// listed for (see ShopriteStore.area). Empty means everywhere.
  final List<String> areas;

  /// Whether a shopper in [area] gets this leaflet.
  bool appliesTo(String? area) =>
      area == null || areas.isEmpty || areas.contains(area);

  Retailer get retailer => Retailer.byId(retailerId);

  /// Whole days left including today; negative once expired; null if unknown.
  int? daysLeft(DateTime now) {
    final end = validTo;
    if (end == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(end.year, end.month, end.day).difference(today).inDays;
  }

  bool isLive(DateTime now) => (daysLeft(now) ?? 0) >= 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'retailer': retailerId,
    'title': title,
    'sourceUrl': sourceUrl,
    if (cover != null) 'cover': cover,
    if (validFrom != null) 'validFrom': _date(validFrom!),
    if (validTo != null) 'validTo': _date(validTo!),
    if (stores != null) 'stores': stores,
    if (firstSeen != null) 'firstSeen': _date(firstSeen!),
    if (areas.isNotEmpty) 'areas': areas,
    'pages': [for (final p in pages) p.toJson()],
  };

  factory Catalogue.fromJson(Map<String, dynamic> j) => Catalogue(
    id: j['id'] as String,
    retailerId: j['retailer'] as String,
    title: j['title'] as String,
    sourceUrl: j['sourceUrl'] as String,
    cover: j['cover'] as String?,
    validFrom: _parseDate(j['validFrom']),
    validTo: _parseDate(j['validTo']),
    stores: j['stores'] as String?,
    firstSeen: _parseDate(j['firstSeen']),
    areas: (j['areas'] as List? ?? const []).cast<String>(),
    pages: [
      for (final p in (j['pages'] as List? ?? const []))
        CataloguePage.fromJson(p as Map<String, dynamic>),
    ],
  );
}

/// What a product cost in an earlier leaflet.
class PricePoint {
  const PricePoint({
    required this.retailerId,
    required this.from,
    required this.price,
    this.to,
  });

  final String retailerId;

  /// The dates the leaflet ran.
  final DateTime from;
  final DateTime? to;
  final double price;

  Retailer get retailer => Retailer.byId(retailerId);

  Map<String, dynamic> toJson() => {
    'retailer': retailerId,
    'from': _date(from),
    if (to != null) 'to': _date(to!),
    'price': price,
  };

  factory PricePoint.fromJson(Map<String, dynamic> j) => PricePoint(
    retailerId: j['retailer'] as String,
    from: DateTime.parse(j['from'] as String),
    to: _parseDate(j['to']),
    price: (j['price'] as num).toDouble(),
  );
}

/// One priced product read from a catalogue page.
class DealItem {
  const DealItem({
    required this.id,
    required this.catalogueId,
    required this.retailerId,
    required this.page,
    required this.name,
    required this.price,
    this.perKg = false,
    this.sizeQty,
    this.sizeUnit,
    this.save,
    this.crop,
    this.groupId,
    this.category = 'Other',
    this.confidence = 1,
    this.history = const [],
    this.box,
    this.corrected = false,
    this.agreed = false,
    this.otherPrice,
    this.firstName,
  });

  final String id;
  final String catalogueId;
  final String retailerId;

  /// 1-based page number inside the catalogue.
  final int page;
  final String name;

  /// Price in kwacha.
  final double price;

  /// True when the price is per kilogram rather than per pack.
  final bool perKg;

  /// Pack size normalised to a base unit: g, ml or count ("ea").
  final double? sizeQty;
  final String? sizeUnit;

  /// Advertised saving in kwacha, when the leaflet prints one.
  final double? save;

  /// Small picture of the item cut from the page; same path rules as pages.
  final String? crop;

  /// Items that look like the same product share a group id.
  final String? groupId;
  final String category;

  /// 0..1, how sure the reader was about this item.
  final double confidence;

  /// Where the whole item (picture, price, description) is on its page:
  /// left, top, width and height as fractions of the page. Null in feeds
  /// made before this was recorded.
  final List<double>? box;

  /// True when a person checked this item against the leaflet and put the
  /// reading right.
  final bool corrected;

  /// Each page is read twice, by two readers that work differently. True
  /// when both gave this price.
  final bool agreed;

  /// The price the second reader gave, when the two differ. The first
  /// reader's price is the one shown; this one is worth a look at the
  /// leaflet.
  final double? otherPrice;

  /// The name as first read, when the second reading repaired it. A
  /// correction made against the earlier name still finds its item.
  final String? firstName;

  /// Worth checking against the leaflet: the readers differ and nobody has
  /// settled it yet.
  bool get inDoubt => otherPrice != null && !corrected;

  /// What the same product cost in leaflets that have since been replaced,
  /// at this shop and at the others. Oldest first.
  final List<PricePoint> history;

  /// The most recent earlier price at this item's own shop.
  PricePoint? get lastPriceHere {
    for (final h in history.reversed) {
      if (h.retailerId == retailerId) return h;
    }
    return null;
  }

  /// How much cheaper this is than the shop's previous leaflet price.
  double? get dropSinceLast {
    final last = lastPriceHere;
    if (last == null) return null;
    // A few ngwee either way is the same price, not a drop.
    final least = last.price * 0.01 > 0.05 ? last.price * 0.01 : 0.05;
    if (last.price - price < least) return null;
    return double.parse((last.price - price).toStringAsFixed(2));
  }

  Retailer get retailer => Retailer.byId(retailerId);

  /// Price per kg, per litre or per unit, when the size is known.
  double? get unitPrice {
    if (perKg) return price;
    final q = sizeQty;
    if (q == null || q <= 0) return null;
    switch (sizeUnit) {
      case 'g':
      case 'ml':
        return price / q * 1000;
      case 'ea':
        return price / q;
    }
    return null;
  }

  String? get unitPriceLabel {
    if (perKg) return 'per kg';
    switch (sizeUnit) {
      case 'g':
        return 'per kg';
      case 'ml':
        return 'per litre';
      case 'ea':
        return 'each';
    }
    return null;
  }

  /// "500 g", "1.5 L", "30 pack"; null when the size is unknown.
  String? get sizeLabel {
    final q = sizeQty;
    if (q == null) return null;
    String n(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    switch (sizeUnit) {
      case 'g':
        return q >= 1000 ? '${n(q / 1000)} kg' : '${n(q)} g';
      case 'ml':
        return q >= 1000 ? '${n(q / 1000)} L' : '${n(q)} ml';
      case 'ea':
        return '${n(q)} pack';
    }
    return null;
  }

  DealItem copyWith({
    String? groupId,
    String? crop,
    String? category,
    List<PricePoint>? history,
    String? name,
    double? price,
    bool? corrected,
  }) => DealItem(
    id: id,
    catalogueId: catalogueId,
    retailerId: retailerId,
    page: page,
    name: name ?? this.name,
    price: price ?? this.price,
    perKg: perKg,
    sizeQty: sizeQty,
    sizeUnit: sizeUnit,
    save: save,
    crop: crop ?? this.crop,
    groupId: groupId ?? this.groupId,
    category: category ?? this.category,
    confidence: confidence,
    history: history ?? this.history,
    box: box,
    corrected: corrected ?? this.corrected,
    agreed: agreed,
    otherPrice: otherPrice,
    firstName: firstName,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'catalogue': catalogueId,
    'retailer': retailerId,
    'page': page,
    'name': name,
    'price': price,
    if (perKg) 'perKg': true,
    if (sizeQty != null) 'sizeQty': sizeQty,
    if (sizeUnit != null) 'sizeUnit': sizeUnit,
    if (save != null) 'save': save,
    if (crop != null) 'crop': crop,
    if (groupId != null) 'group': groupId,
    'category': category,
    'confidence': double.parse(confidence.toStringAsFixed(2)),
    if (history.isNotEmpty) 'history': [for (final h in history) h.toJson()],
    if (box != null) 'box': box,
    if (corrected) 'corrected': true,
    if (agreed) 'agreed': true,
    if (otherPrice != null) 'otherPrice': otherPrice,
    if (firstName != null) 'firstName': firstName,
  };

  factory DealItem.fromJson(Map<String, dynamic> j) => DealItem(
    id: j['id'] as String,
    catalogueId: j['catalogue'] as String,
    retailerId: j['retailer'] as String,
    page: j['page'] as int,
    name: j['name'] as String,
    price: (j['price'] as num).toDouble(),
    perKg: j['perKg'] as bool? ?? false,
    sizeQty: (j['sizeQty'] as num?)?.toDouble(),
    sizeUnit: j['sizeUnit'] as String?,
    save: (j['save'] as num?)?.toDouble(),
    crop: j['crop'] as String?,
    groupId: j['group'] as String?,
    category: j['category'] as String? ?? 'Other',
    confidence: (j['confidence'] as num?)?.toDouble() ?? 1,
    history: [
      for (final h in (j['history'] as List? ?? const []))
        PricePoint.fromJson(h as Map<String, dynamic>),
    ],
    box: (j['box'] as List?)?.map((v) => (v as num).toDouble()).toList(),
    corrected: j['corrected'] as bool? ?? false,
    agreed: j['agreed'] as bool? ?? false,
    otherPrice: (j['otherPrice'] as num?)?.toDouble(),
    firstName: j['firstName'] as String?,
  );
}

class Feed {
  const Feed({
    required this.generatedAt,
    required this.catalogues,
    required this.items,
  });

  final DateTime generatedAt;
  final List<Catalogue> catalogues;
  final List<DealItem> items;

  static final empty = Feed(
    generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    catalogues: const [],
    items: const [],
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'catalogues': [for (final c in catalogues) c.toJson()],
    'items': [for (final i in items) i.toJson()],
  };

  factory Feed.fromJson(Map<String, dynamic> j) => Feed(
    generatedAt: DateTime.parse(j['generatedAt'] as String).toLocal(),
    catalogues: [
      for (final c in (j['catalogues'] as List? ?? const []))
        Catalogue.fromJson(c as Map<String, dynamic>),
    ],
    items: [
      for (final i in (j['items'] as List? ?? const []))
        DealItem.fromJson(i as Map<String, dynamic>),
    ],
  );
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// A person's fix to one reading: what the leaflet really says, for the item
/// that was read as [readName] at [readPrice] on [page] of [leaflet].
class Correction {
  const Correction({
    required this.leaflet,
    required this.page,
    required this.readName,
    required this.readPrice,
    this.name,
    this.price,
    this.remove = false,
  });

  /// Catalogue id.
  final String leaflet;
  final int page;
  final String readName;
  final double readPrice;

  /// The right name and price; null leaves that part as it was read.
  final String? name;
  final double? price;

  /// True when what was read is not a product at all.
  final bool remove;

  bool matches(DealItem i) =>
      i.catalogueId == leaflet &&
      i.page == page &&
      (i.name == readName || i.firstName == readName) &&
      (i.price - readPrice).abs() < 0.005;

  Map<String, dynamic> toJson() => {
    'leaflet': leaflet,
    'page': page,
    'read': {'name': readName, 'price': readPrice},
    if (remove) 'remove': true else 'correct': {'name': ?name, 'price': ?price},
  };

  /// Null when [j] is not a usable correction. Lenient about types and
  /// strict about values, since this is read from text a person submitted.
  static Correction? tryParse(Object? j) {
    if (j is! Map) return null;
    final read = j['read'];
    final leaflet = j['leaflet'], page = j['page'];
    if (read is! Map || leaflet is! String || page is! int) return null;
    final readName = read['name'], readPrice = read['price'];
    if (readName is! String || readPrice is! num) return null;
    if (leaflet.length > 200 || readName.length > 200) return null;

    final remove = j['remove'] == true;
    final correct = j['correct'];
    String? name;
    double? price;
    if (correct is Map) {
      final n = correct['name'], p = correct['price'];
      if (n is String) {
        final clean = n.replaceAll(RegExp(r'[\x00-\x1f]'), ' ').trim();
        if (clean.isEmpty || clean.length > 120) return null;
        name = clean;
      }
      if (p is num) {
        if (p <= 0 || p > 1000000) return null;
        price = double.parse(p.toStringAsFixed(2));
      }
    }
    if (!remove && name == null && price == null) return null;
    return Correction(
      leaflet: leaflet,
      page: page,
      readName: readName,
      readPrice: readPrice.toDouble(),
      name: name,
      price: price,
      remove: remove,
    );
  }
}

/// Applies [corrections] to [items]: fixed items are marked corrected, and
/// the ones that were not products are dropped.
List<DealItem> applyCorrections(
  List<DealItem> items,
  Iterable<Correction> corrections,
) {
  final list = corrections.toList();
  if (list.isEmpty) return items;
  final out = <DealItem>[];
  for (final item in items) {
    Correction? fix;
    // The latest correction for an item wins.
    for (final c in list) {
      if (c.matches(item)) fix = c;
    }
    if (fix == null) {
      out.add(item);
    } else if (!fix.remove) {
      out.add(item.copyWith(name: fix.name, price: fix.price, corrected: true));
    }
  }
  return out;
}
