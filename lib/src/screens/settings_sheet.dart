import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../shoprite_stores.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalogue_viewer.dart';

void showSettingsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  TextEditingController? _url;
  bool _saving = false;

  @override
  void dispose() {
    _url?.dispose();
    super.dispose();
  }

  String _ago(DateTime t, DateTime now) {
    if (t.millisecondsSinceEpoch == 0) return 'never';
    final d = now.difference(t);
    if (d.inMinutes < 60) return 'less than an hour ago';
    if (d.inHours < 24) {
      return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
    }
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago, on ${shortDate(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final url = _url ??= TextEditingController(text: s.feedUrl);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('Settings'),
            const SizedBox(height: 20),
            Text(
              'Where specials come from',
              style: display(context, size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Leaflets are collected from each shop\'s own Zambian specials '
              'page. Last collected ${_ago(s.feed.generatedAt, s.now)}.',
              style: TextStyle(fontSize: 14.5, color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 8),
            for (final r in Retailer.all)
              InkWell(
                onTap: () => openOnShopSite(context, r.website),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(child: RetailerMark(r, fontSize: 15)),
                      Text(
                        'Open specials page',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Your Shoprite',
              style: display(context, size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Shoprite\'s leaflets can differ by province and by kind of '
              'shop. Choose your store to see only the leaflets that apply '
              'there.',
              style: TextStyle(fontSize: 14.5, color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final picked = await showShopriteStorePicker(
                    context,
                    current: s.shopriteStore,
                  );
                  if (picked != null) await s.setShopriteStore(picked.store);
                },
                child: Text(
                  s.shopriteStore == null
                      ? 'All Shoprite stores'
                      : '${s.shopriteStore!.label}, ${s.shopriteStore!.city}',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Feed address',
              style: display(context, size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'The web address of a hosted feed.json. With an address set, '
              'the app downloads new specials when it opens and when you '
              'pull down to refresh. Leave it empty to use the specials '
              'saved with the app.',
              style: TextStyle(fontSize: 14.5, color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'https://example.com/specials/feed.json',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _saving = true);
                        await s.setFeedUrl(url.text);
                        final notice = s.takeNotice();
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(notice ?? 'Feed address saved.'),
                          ),
                        );
                      },
                child: Text(_saving ? 'Saving' : 'Save feed address'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the store picker returns: a store, or null inside for "all stores".
/// (A plain null from the picker means it was dismissed.)
class StoreChoice {
  const StoreChoice(this.store);
  final ShopriteStore? store;
}

Future<StoreChoice?> showShopriteStorePicker(
  BuildContext context, {
  ShopriteStore? current,
}) {
  return showModalBottomSheet<StoreChoice>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _StorePicker(current: current),
  );
}

class _StorePicker extends StatefulWidget {
  const _StorePicker({this.current});

  final ShopriteStore? current;

  @override
  State<_StorePicker> createState() => _StorePickerState();
}

class _StorePickerState extends State<_StorePicker> {
  String _query = '';

  /// "Lusaka", "Chingola, Copperbelt": the town, and the province when it
  /// has a different name.
  String _where(ShopriteStore s) {
    if (s.city == s.province) return s.city;
    if (s.city == s.name) return s.province;
    return '${s.city}, ${s.province}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final stores =
        shopriteStores.where((s) {
          final text = '${s.label} ${s.city} ${s.province}'.toLowerCase();
          return words.every(text.contains);
        }).toList()..sort((a, b) {
          final c = a.city.compareTo(b.city);
          return c != 0 ? c : a.name.compareTo(b.name);
        });

    Widget row(
      String title,
      String? detail,
      bool selected,
      StoreChoice choice,
    ) {
      return InkWell(
        onTap: () => Navigator.of(context).pop(choice),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        style: TextStyle(fontSize: 13, color: p.inkSoft),
                      ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_rounded, color: p.green, size: 22),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Your Shoprite'),
              const SizedBox(height: 12),
              TextField(
                autocorrect: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search by store or town',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (words.isEmpty)
                      row(
                        'All Shoprite stores',
                        'Show every Shoprite leaflet',
                        widget.current == null,
                        const StoreChoice(null),
                      ),
                    for (final s in stores)
                      row(
                        s.label,
                        _where(s),
                        widget.current?.id == s.id,
                        StoreChoice(s),
                      ),
                    if (stores.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No store matches "$_query". Try the town\'s name.',
                          style: TextStyle(fontSize: 14.5, color: p.inkSoft),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
