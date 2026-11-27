import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'shoprite_stores.dart';

const _bundledFeed = 'assets/data/feed.json';

/// Where the app looks for fresh specials unless settings say otherwise.
/// Another feed can be compiled in with
/// flutter build ... --dart-define=FEED_URL=https://.../feed.json
const builtInFeedUrl = String.fromEnvironment(
  'FEED_URL',
  defaultValue: 'https://dynamite112lc.github.io/zed-specials/feed.json',
);
const _kFeedUrl = 'feedUrl';
const _kWatch = 'watchlist';
const _kSeen = 'seenCatalogues';
const _kCachedFeed = 'cachedFeed';
const _kShopriteStore = 'shopriteStore';

/// A set of items that look like the same product at different shops.
class PriceGroup {
  PriceGroup(this.id, this.items);

  final String id;

  /// Cheapest first, by unit price when every item has one.
  final List<DealItem> items;

  DealItem get best => items.first;
  bool get comparesUnitPrice => items.every((i) => i.unitPrice != null);
  double valueOf(DealItem i) => comparesUnitPrice ? i.unitPrice! : i.price;
  int get shopCount => items.map((i) => i.retailerId).toSet().length;

  /// How much more the dearest option costs than the cheapest, as a fraction.
  double get spread {
    final lo = valueOf(items.first), hi = valueOf(items.last);
    return lo <= 0 ? 0 : (hi - lo) / lo;
  }
}

class AppState extends ChangeNotifier {
  Feed feed = Feed.empty;
  bool loading = true;
  bool refreshing = false;

  /// Shown once after a refresh attempt; cleared when read.
  String? notice;

  /// Empty means every shop.
  final Set<String> shops = {};
  List<String> watchlist = [];
  Set<String> seen = {};
  String feedUrl = '';

  /// The shopper's own Shoprite, when they have chosen one. Shoprite's
  /// leaflets differ by province and by kind of shop; with a store chosen
  /// only the leaflets that apply there are shown.
  ShopriteStore? shopriteStore;

  Uri? _remoteBase;
  SharedPreferences? _prefs;
  DateTime? _lastRefresh;

  DateTime get now => DateTime.now();

  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    feedUrl = _prefs!.getString(_kFeedUrl) ?? builtInFeedUrl;
    watchlist = _prefs!.getStringList(_kWatch) ?? [];
    shopriteStore = shopriteStoreById(_prefs!.getInt(_kShopriteStore));
    final seenList = _prefs!.getStringList(_kSeen);
    seen = seenList?.toSet() ?? {};

    try {
      final raw = await rootBundle.loadString(_bundledFeed);
      feed = Feed.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      feed = Feed.empty;
    }

    // A previously downloaded feed wins if it is newer than the bundled one.
    final cached = _prefs!.getString(_kCachedFeed);
    if (cached != null && feedUrl.isNotEmpty) {
      try {
        final f = Feed.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        if (f.generatedAt.isAfter(feed.generatedAt)) {
          feed = f;
          _remoteBase = Uri.parse(feedUrl);
        }
      } catch (_) {}
    }

    // First run: nothing is "new" yet.
    if (seenList == null) {
      seen = feed.catalogues.map((c) => c.id).toSet();
      await _prefs!.setStringList(_kSeen, seen.toList());
    }

    loading = false;
    notifyListeners();
    if (feedUrl.isNotEmpty) refresh(silent: true);
  }

  /// Downloads the latest feed from the address in settings.
  Future<void> refresh({bool silent = false}) async {
    if (feedUrl.isEmpty) {
      if (!silent) {
        notice =
            'Showing the specials saved with the app. Add a feed '
            'address in settings to get updates.';
        notifyListeners();
      }
      return;
    }
    refreshing = true;
    _lastRefresh = now;
    notifyListeners();
    try {
      final uri = Uri.parse(feedUrl);
      final res = await http.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw 'The feed replied ${res.statusCode}';
      final body = utf8.decode(res.bodyBytes);
      final f = Feed.fromJson(jsonDecode(body) as Map<String, dynamic>);
      feed = f;
      _remoteBase = uri;
      await _prefs?.setString(_kCachedFeed, body);
      if (!silent) notice = 'Specials are up to date.';
    } catch (e) {
      if (!silent) {
        notice =
            "Couldn't update. Check your connection and the feed "
            'address in settings.';
      }
    }
    refreshing = false;
    notifyListeners();
  }

  /// Quietly checks for new specials when the last check was hours ago.
  /// Called when the app comes back to the foreground.
  Future<void> refreshIfStale() async {
    if (loading || refreshing || feedUrl.isEmpty) return;
    final last = _lastRefresh;
    if (last != null && now.difference(last) < const Duration(hours: 3)) {
      return;
    }
    await refresh(silent: true);
  }

  String? takeNotice() {
    final n = notice;
    notice = null;
    return n;
  }

  Future<void> setFeedUrl(String url) async {
    feedUrl = url.trim();
    await _prefs?.setString(_kFeedUrl, feedUrl);
    if (feedUrl.isEmpty) {
      _remoteBase = null;
      await _prefs?.remove(_kCachedFeed);
      final raw = await rootBundle.loadString(_bundledFeed);
      feed = Feed.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    } else {
      await refresh();
    }
  }

  Future<void> setShopriteStore(ShopriteStore? store) async {
    shopriteStore = store;
    if (store == null) {
      await _prefs?.remove(_kShopriteStore);
    } else {
      await _prefs?.setInt(_kShopriteStore, store.id);
    }
    notifyListeners();
  }

  /// Whether a catalogue applies where this shopper shops.
  bool _mine(Catalogue c) =>
      c.retailerId != Retailer.shoprite.id || c.appliesTo(shopriteStore?.area);

  // ------------------------------------------------------------- images

  /// Resolves a feed image: absolute URLs load as they are, relative paths
  /// from the folder of the hosted feed. Leaflet pictures are not packed
  /// into the app: they change every week and would be stale within days.
  ImageProvider image(String path) {
    if (path.startsWith('http')) return NetworkImage(path);
    final base =
        _remoteBase ?? (feedUrl.isEmpty ? null : Uri.tryParse(feedUrl));
    if (base != null) return NetworkImage(base.resolve(path).toString());
    return AssetImage('assets/data/$path');
  }

  // ------------------------------------------------------------ filters

  void toggleShop(String? id) {
    if (id == null) {
      shops.clear();
    } else if (!shops.remove(id)) {
      shops.add(id);
      if (shops.length == Retailer.all.length) shops.clear();
    }
    notifyListeners();
  }

  bool _shopOn(String id) => shops.isEmpty || shops.contains(id);

  /// Catalogues still valid today, soonest to end first.
  List<Catalogue> get liveCatalogues {
    final list = feed.catalogues
        .where((c) => c.isLive(now) && _shopOn(c.retailerId) && _mine(c))
        .toList();
    list.sort(
      (a, b) => (a.daysLeft(now) ?? 999).compareTo(b.daysLeft(now) ?? 999),
    );
    return list;
  }

  int get liveCatalogueCountAllShops =>
      feed.catalogues.where((c) => c.isLive(now) && _mine(c)).length;

  Catalogue? catalogue(String id) {
    for (final c in feed.catalogues) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Items from catalogues that are still valid, for the chosen shops.
  List<DealItem> get liveItems {
    final live = {
      for (final c in feed.catalogues)
        if (c.isLive(now) && _mine(c)) c.id,
    };
    return feed.items
        .where((i) => live.contains(i.catalogueId) && _shopOn(i.retailerId))
        .toList();
  }

  List<DealItem> itemsOnPage(String catalogueId, int page) => feed.items
      .where((i) => i.catalogueId == catalogueId && i.page == page)
      .toList();

  List<String> get categories {
    final counts = <String, int>{};
    for (final i in liveItems) {
      counts[i.category] = (counts[i.category] ?? 0) + 1;
    }
    final list = counts.keys.toList()
      ..sort((a, b) {
        if (a == 'Other') return 1;
        if (b == 'Other') return -1;
        return counts[b]!.compareTo(counts[a]!);
      });
    return list;
  }

  // ------------------------------------------------------------ compare

  /// Groups of the same product sold by at least two shops this week.
  List<PriceGroup> get crossShopGroups {
    final byGroup = <String, List<DealItem>>{};
    for (final i in liveItems) {
      final g = i.groupId;
      if (g != null) byGroup.putIfAbsent(g, () => []).add(i);
    }
    final groups = <PriceGroup>[];
    byGroup.forEach((id, items) {
      final g = _sorted(id, items);
      if (g.shopCount >= 2) groups.add(g);
    });
    groups.sort((a, b) => b.spread.compareTo(a.spread));
    return groups;
  }

  PriceGroup? groupOf(DealItem item) {
    final g = item.groupId;
    if (g == null) return null;
    final items = liveItems.where((i) => i.groupId == g).toList();
    return items.length < 2 ? null : _sorted(g, items);
  }

  PriceGroup _sorted(String id, List<DealItem> items) {
    final unit = items.every((i) => i.unitPrice != null);
    items.sort(
      (a, b) => (unit ? a.unitPrice! : a.price).compareTo(
        unit ? b.unitPrice! : b.price,
      ),
    );
    return PriceGroup(id, items);
  }

  /// Items whose name contains every word of [query], cheapest first.
  List<DealItem> search(String query, {Iterable<DealItem>? within}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    final hits = (within ?? liveItems).where((i) {
      final name = i.name.toLowerCase();
      return words.every(name.contains);
    }).toList();
    // When most hits have a pack size, rank by unit price and put the few
    // without one last; otherwise fall back to shelf price.
    final sized = hits.where((i) => i.unitPrice != null).length;
    if (sized * 2 >= hits.length && sized > 0) {
      hits.sort((a, b) {
        final ua = a.unitPrice, ub = b.unitPrice;
        if (ua == null && ub == null) return a.price.compareTo(b.price);
        if (ua == null) return 1;
        if (ub == null) return -1;
        return ua.compareTo(ub);
      });
    } else {
      hits.sort((a, b) => a.price.compareTo(b.price));
    }
    return hits;
  }

  // ---------------------------------------------------------- watchlist

  bool isWatched(String term) =>
      watchlist.any((w) => w.toLowerCase() == term.trim().toLowerCase());

  Future<void> watch(String term) async {
    final t = term.trim();
    if (t.isEmpty || isWatched(t)) return;
    watchlist = [t, ...watchlist];
    await _prefs?.setStringList(_kWatch, watchlist);
    notifyListeners();
  }

  Future<void> unwatch(String term) async {
    watchlist = watchlist.where((w) => w != term).toList();
    await _prefs?.setStringList(_kWatch, watchlist);
    notifyListeners();
  }

  /// How many watched items are on special right now.
  int get watchHits {
    final items = feed.items.isEmpty ? const <DealItem>[] : _allLiveItems;
    return watchlist.where((w) => search(w, within: items).isNotEmpty).length;
  }

  List<DealItem> get _allLiveItems {
    final live = {
      for (final c in feed.catalogues)
        if (c.isLive(now) && _mine(c)) c.id,
    };
    return feed.items.where((i) => live.contains(i.catalogueId)).toList();
  }

  List<DealItem> watchMatches(String term) =>
      search(term, within: _allLiveItems);

  // ------------------------------------------------------ new catalogues

  bool isNew(Catalogue c) => !seen.contains(c.id);

  Future<void> markSeen(Catalogue c) async {
    if (seen.add(c.id)) {
      await _prefs?.setStringList(_kSeen, seen.toList());
      notifyListeners();
    }
  }
}

/// Makes [AppState] available to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// For callbacks: does not subscribe to changes.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

String formatPrice(double v) {
  final whole = v == v.roundToDouble();
  final s = whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  final parts = s.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return parts.length > 1 ? 'K$buf.${parts[1]}' : 'K$buf';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]}';

/// The run of a leaflet: "3 to 16 Nov", "28 Oct to 3 Nov", with the year
/// when it is not this one.
String rangeLabel(DateTime from, DateTime? to, DateTime now) {
  String day(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';
  final end = to ?? from;
  final year = end.year == now.year ? '' : ' ${end.year}';
  final oneDay =
      from.year == end.year && from.month == end.month && from.day == end.day;
  if (oneDay) return '${day(from)}$year';
  final sameMonth = from.year == end.year && from.month == end.month;
  return '${sameMonth ? '${from.day}' : day(from)} to ${day(end)}$year';
}

/// "Ends today", "Ends tomorrow", "Ends Sun 29 Nov".
String endsLabel(Catalogue c, DateTime now) {
  final days = c.daysLeft(now);
  if (days == null || c.validTo == null) return 'No end date given';
  if (days < 0) return 'Ended ${shortDate(c.validTo!)}';
  if (days == 0) return 'Ends today';
  if (days == 1) return 'Ends tomorrow';
  return 'Ends ${shortDate(c.validTo!)}';
}
