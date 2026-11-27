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
    pages: [
      for (final p in (j['pages'] as List? ?? const []))
        CataloguePage.fromJson(p as Map<String, dynamic>),
    ],
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

  DealItem copyWith({String? groupId, String? crop, String? category}) =>
      DealItem(
        id: id,
        catalogueId: catalogueId,
        retailerId: retailerId,
        page: page,
        name: name,
        price: price,
        perKg: perKg,
        sizeQty: sizeQty,
        sizeUnit: sizeUnit,
        save: save,
        crop: crop ?? this.crop,
        groupId: groupId ?? this.groupId,
        category: category ?? this.category,
        confidence: confidence,
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
