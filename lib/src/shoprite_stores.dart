// Shoprite's stores in Zambia, as its own store locator listed them on
// 2026-11-27 (looked up by hand, once; the feed builder never asks for this
// list). Shoprite shows each store the leaflets for its province and its
// kind of shop, so stores of the same kind in the same province see the
// same leaflets. The province numbers are Shoprite's own, and so are a few
// odd placements (Chilenje under Eastern Province): they are what its site
// uses when it picks a store's leaflets.
//
// Pure Dart: shared by the app (store picker) and the feed builder.

class ShopriteStore {
  const ShopriteStore(
    this.id,
    this.brand,
    this.name,
    this.city,
    this.provinceId,
    this.province,
  );

  /// Shoprite's number for the store.
  final int id;

  /// "Shoprite", "Shoprite Select", "Shoprite Mini" or "Shoprite LiquorShop".
  final String brand;
  final String name;
  final String city;
  final int provinceId;
  final String province;

  /// Stores with the same area see the same leaflets.
  String get area => '$provinceId|$brand';

  /// "Shoprite Select Manda Hill"
  String get label => '$brand $name';
}

const shopriteStores = <ShopriteStore>[
  ShopriteStore(2808, 'Shoprite', 'Cairo Road', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(2816, 'Shoprite', 'Ndola', 'Ndola', 298, 'Copperbelt'),
  ShopriteStore(2824, 'Shoprite', 'Kabwe', 'Kabwe', 297, 'Central'),
  ShopriteStore(2832, 'Shoprite', 'Kitwe', 'Kitwe', 298, 'Copperbelt'),
  ShopriteStore(2840, 'Shoprite', 'Livingstone', 'Livingstone', 304, 'Southern'),
  ShopriteStore(2858, 'Shoprite', 'Mufulira', 'Mufulira', 298, 'Copperbelt'),
  ShopriteStore(2866, 'Shoprite', 'Chingola', 'Chingola', 298, 'Copperbelt'),
  ShopriteStore(2890, 'Shoprite', 'Solwezi', 'Solwezi', 303, 'North-Western'),
  ShopriteStore(2913, 'Shoprite', 'Chipata', 'Chipata', 299, 'Eastern'),
  ShopriteStore(2921, 'Shoprite', 'Matero', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(2939, 'Shoprite', 'Mazabuka', 'Mazabuka', 304, 'Southern'),
  ShopriteStore(2955, 'Shoprite', 'Mansa', 'Mansa', 300, 'Luapula'),
  ShopriteStore(2963, 'Shoprite', 'Chilenje', 'Lusaka', 299, 'Eastern'),
  ShopriteStore(2989, 'Shoprite', 'Kasama', 'Kasama', 302, 'Northern'),
  ShopriteStore(2997, 'Shoprite Select', 'Manda Hill', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(5903, 'Shoprite Mini', 'Kafue Road', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(31097, 'Shoprite', 'Jacaranda Mall', 'Ndola', 298, 'Copperbelt'),
  ShopriteStore(31364, 'Shoprite Mini', 'Chimwemwe', 'Kitwe', 298, 'Copperbelt'),
  ShopriteStore(34906, 'Shoprite', 'Roan Mall', 'Luanshya', 298, 'Copperbelt'),
  ShopriteStore(34922, 'Shoprite Select', 'Waterfalls', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(35740, 'Shoprite', 'Mulungushi Kabwe', 'Kabwe', 297, 'Central'),
  ShopriteStore(35766, 'Shoprite Mini', 'Chirundu', 'Chirundu', 304, 'Southern'),
  ShopriteStore(37938, 'Shoprite', 'Twin Palms', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(37946, 'Shoprite Select', 'Kafubu Mall', 'Ndola', 298, 'Copperbelt'),
  ShopriteStore(37954, 'Shoprite', 'The Park Chingola', 'Chingola', 298, 'Copperbelt'),
  ShopriteStore(39875, 'Shoprite Mini', 'Munali', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(39883, 'Shoprite Select', 'Kabulonga', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(55615, 'Shoprite Select', 'Mosi-oa-tunya', 'Livingstone', 304, 'Southern'),
  ShopriteStore(64824, 'Shoprite', 'Chililabombwe', 'Chingola', 298, 'Copperbelt'),
  ShopriteStore(64832, 'Shoprite Select', 'Solwezi City Mall', 'Solwezi', 303, 'North-Western'),
  ShopriteStore(70768, 'Shoprite', 'Unza', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(81458, 'Shoprite', 'Great North', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(81474, 'Shoprite Mini', 'Kapiri Mposhi', 'Kapiri Mposhi', 298, 'Copperbelt'),
  ShopriteStore(84723, 'Shoprite Select', 'Mukuba Mall', 'Kitwe', 298, 'Copperbelt'),
  ShopriteStore(84799, 'Shoprite', 'Barotse Mall', 'Mongu', 305, 'Western'),
  ShopriteStore(85185, 'Shoprite Mini', 'Kalingalinga', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(91184, 'Shoprite Select', 'East Park Mall', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(94433, 'Shoprite', 'Lusaka Woodlands', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(96948, 'Shoprite Select', 'Cosmopolitan Mall', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(99158, 'Shoprite Mini', 'Kabwata', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(99302, 'Shoprite Mini', 'Bauleni', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(164266, 'Shoprite', 'Levy Junction', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(164274, 'Shoprite', 'Kasama Central', 'Kasama', 302, 'Northern'),
  ShopriteStore(164282, 'Shoprite Mini', 'SE Chalala', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(164973, 'Shoprite LiquorShop', 'Ibex Hill', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(166048, 'Shoprite Mini', 'Mungwi', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(166064, 'Shoprite Mini', 'Ibex Hill', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(169711, 'Shoprite LiquorShop', 'Mungwi', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(169999, 'Shoprite Mini', 'Rossfort Mall', 'Lusaka', 301, 'Lusaka'),
  ShopriteStore(170003, 'Shoprite Mini', 'Kabanana Road', 'Lusaka', 301, 'Lusaka'),
];

ShopriteStore? shopriteStoreById(int? id) {
  if (id == null) return null;
  for (final s in shopriteStores) {
    if (s.id == id) return s;
  }
  return null;
}

/// One store for every area: asking these covers every store's leaflets.
List<ShopriteStore> get shopriteAreaStores {
  final seen = <String>{};
  return [
    for (final s in shopriteStores)
      if (seen.add(s.area)) s,
  ];
}

/// Says in words where a leaflet applies, from the areas it was listed for:
/// "All Shoprite stores", "LiquorShop stores", "Copperbelt and Lusaka stores".
String describeShopriteAreas(Iterable<String> areas) {
  final have = areas.toSet();
  if (have.isEmpty) return 'Shoprite stores';
  final all = {for (final s in shopriteStores) s.area};
  bool liquor(String a) => a.endsWith('|Shoprite LiquorShop');
  final supermarkets = all.where((a) => !liquor(a)).toSet();
  final liquorShops = all.where(liquor).toSet();

  final hasAllSupermarkets = have.containsAll(supermarkets);
  final hasAllLiquor = liquorShops.isNotEmpty && have.containsAll(liquorShops);
  if (hasAllSupermarkets && hasAllLiquor) return 'All Shoprite stores';
  if (hasAllSupermarkets && !have.any(liquor)) {
    return 'All Shoprite supermarkets';
  }
  if (have.every(liquor)) {
    return hasAllLiquor
        ? 'Shoprite LiquorShop stores'
        : 'Some Shoprite LiquorShop stores';
  }

  // Otherwise name the kinds of shop and the provinces.
  final brands = <String>{}, provinces = <String>{};
  for (final s in shopriteStores) {
    if (have.contains(s.area)) {
      brands.add(s.brand);
      provinces.add(s.province);
    }
  }
  String list(List<String> items) => items.length <= 1
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  final everyBrand = {for (final s in shopriteStores) s.brand};
  final kinds = brands.length == everyBrand.length
      ? 'Shoprite stores'
      : '${list(brands.toList()..sort())} stores';
  return '$kinds in ${list(provinces.toList()..sort())}';
}
