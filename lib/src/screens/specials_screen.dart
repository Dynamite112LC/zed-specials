import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalogue_viewer.dart';
import 'item_sheet.dart';
import 'settings_sheet.dart';

enum _Sort { lowest, saving, drop }

/// This week's leaflets and every price read from them.
class SpecialsScreen extends StatefulWidget {
  const SpecialsScreen({super.key});

  @override
  State<SpecialsScreen> createState() => _SpecialsScreenState();
}

class _SpecialsScreenState extends State<SpecialsScreen>
    with SingleTickerProviderStateMixin {
  String? _category;
  _Sort _sort = _Sort.saving;

  // One entrance: the leaflets settle onto the shelf when the app opens.
  late final AnimationController _shelf = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shelf.status == AnimationStatus.dismissed) {
      if (MediaQuery.of(context).disableAnimations) {
        _shelf.value = 1;
      } else {
        _shelf.forward();
      }
    }
  }

  @override
  void dispose() {
    _shelf.dispose();
    super.dispose();
  }

  String _headline(AppState s) {
    final live = s.liveCatalogues;
    if (live.isEmpty) return 'No leaflets are running right now.';
    final n = live.length;
    final count = '$n leaflet${n == 1 ? '' : 's'} running';
    final soon = live.where((c) => (c.daysLeft(s.now) ?? 99) <= 3).toList();
    if (soon.isEmpty) return '$count this week.';
    final days = soon.first.daysLeft(s.now)!;
    final same = soon.where((c) => c.daysLeft(s.now) == days).length;
    final when = days == 0
        ? 'today'
        : days == 1
        ? 'tomorrow'
        : 'on ${_dayName(soon.first.validTo!)}';
    return '$count.\n$same end${same == 1 ? 's' : ''} $when.';
  }

  String _dayName(DateTime d) => const [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ][d.weekday - 1];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final catalogues = s.liveCatalogues;
    final categories = s.categories;
    if (_category != null && !categories.contains(_category)) _category = null;

    var items = s.liveItems;
    if (_category != null) {
      items = items.where((i) => i.category == _category).toList();
    }
    if (_sort == _Sort.saving) {
      items.sort((a, b) {
        final c = (b.save ?? 0).compareTo(a.save ?? 0);
        return c != 0 ? c : a.price.compareTo(b.price);
      });
    } else if (_sort == _Sort.drop) {
      // Share of the old price knocked off, so K5 off K20 beats K5 off K200.
      double share(DealItem i) {
        final d = i.dropSinceLast;
        return d == null ? 0 : d / (i.price + d);
      }

      items.sort((a, b) {
        final c = share(b).compareTo(share(a));
        return c != 0 ? c : a.price.compareTo(b.price);
      });
    } else {
      items.sort((a, b) => a.price.compareTo(b.price));
    }

    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 720;

    return RefreshIndicator(
      onRefresh: () => s.refresh(),
      color: p.ink,
      backgroundColor: p.tag,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: ContentWidth(
                child: Padding(
                  padding: EdgeInsets.only(top: wide ? 36 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${shortDate(s.now)}, Zambia',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: p.inkSoft,
                              ),
                            ),
                          ),
                          if (s.refreshing)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: () => showSettingsSheet(context),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Semantics(
                          header: true,
                          child: Text(
                            _headline(s),
                            style: display(context, size: wide ? 46 : 34),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ShopFilter(state: s),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ---------------------------------------------------- leaflets
          SliverToBoxAdapter(
            child: catalogues.isEmpty
                ? ContentWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: _Empty(
                        title: 'Nothing on the shelf',
                        body: s.feed.catalogues.isEmpty
                            ? 'No specials have been loaded yet. Pull down to '
                                  'check again.'
                            : 'The leaflets saved here have all ended. Pull '
                                  'down to look for new ones.',
                      ),
                    ),
                  )
                : SizedBox(
                    height: 156 / 0.7 + 150,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
                          itemCount: catalogues.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            final c = catalogues[i];
                            final start = (i * 0.09).clamp(0.0, 0.6);
                            final anim = CurvedAnimation(
                              parent: _shelf,
                              curve: Interval(
                                start,
                                (start + 0.45).clamp(0.0, 1.0),
                                curve: Curves.easeOutCubic,
                              ),
                            );
                            return AnimatedBuilder(
                              animation: anim,
                              builder: (context, child) => Opacity(
                                opacity: anim.value,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - anim.value) * 26),
                                  child: child,
                                ),
                              ),
                              child: LeafletCard(
                                c,
                                tilt: i.isEven ? -0.012 : 0.014,
                                onTap: () => openCatalogue(context, c),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),

          // ------------------------------------------------------ prices
          if (s.liveItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: SectionTitle(
                          'Prices on special',
                          detail:
                              '${items.length} price${items.length == 1 ? '' : 's'} read from the leaflets',
                        ),
                      ),
                      _SortButton(
                        sort: _sort,
                        onChanged: (v) => setState(() => _sort = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _Pill(
                          label: 'Everything',
                          selected: _category == null,
                          onTap: () => setState(() => _category = null),
                        ),
                        for (final c in categories)
                          _Pill(
                            label: c,
                            selected: _category == c,
                            onTap: () => setState(() => _category = c),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                // Line the grid up with the centred content column.
                final across = constraints.crossAxisExtent;
                final side = (across > 1120 ? (across - 1120) / 2 : 0.0) + 20;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 16, side, 32),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 210,
                          mainAxisExtent: 268,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => DealTile(
                      items[i],
                      onTap: () => showItemSheet(context, items[i]),
                    ),
                  ),
                );
              },
            ),
          ] else if (catalogues.isNotEmpty)
            SliverToBoxAdapter(
              child: ContentWidth(
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: _Empty(
                    title: 'No prices read yet',
                    body:
                        'Open a leaflet to browse it page by page. Prices '
                        'appear here once the leaflets have been read.',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShopFilter extends StatelessWidget {
  const _ShopFilter({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Pill(
          label: 'All shops',
          selected: state.shops.isEmpty,
          onTap: () => state.toggleShop(null),
        ),
        for (final r in Retailer.all)
          _Pill(
            label: r.name,
            dot: Color(0xFF000000 | r.color),
            selected: state.shops.contains(r.id),
            onTap: () => state.toggleShop(r.id),
            trailingMargin: 0,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
    this.trailingMargin = 8,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  final double trailingMargin;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.only(right: trailingMargin),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? p.ink : p.surface,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? p.ink : p.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dot != null) ...[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dot,
                          borderRadius: BorderRadius.circular(3),
                          border: selected
                              ? Border.all(color: p.paper, width: 1)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? p.paper : p.ink,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final _Sort sort;
  final ValueChanged<_Sort> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PopupMenuButton<_Sort>(
      tooltip: 'Change the order',
      initialValue: sort,
      onSelected: onChanged,
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => const [
        PopupMenuItem(value: _Sort.saving, child: Text('Biggest saving first')),
        PopupMenuItem(value: _Sort.lowest, child: Text('Lowest price first')),
        PopupMenuItem(
          value: _Sort.drop,
          child: Text('Biggest drop since last leaflet'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 20, color: p.ink),
            const SizedBox(width: 4),
            Text(
              switch (sort) {
                _Sort.saving => 'Biggest saving',
                _Sort.lowest => 'Lowest price',
                _Sort.drop => 'Biggest drop',
              },
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: display(context, size: 20, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(body, style: TextStyle(fontSize: 15, color: p.inkSoft)),
          ),
        ],
      ),
    );
  }
}
