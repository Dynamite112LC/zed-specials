import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_sheet.dart';
import 'catalogue_viewer.dart' show PriceRow;

/// Everyday items people compare. Only the ones on special are offered.
const _staples = [
  'Cooking oil', 'Sugar', 'Rice', 'Mealie meal', 'Chicken', 'Milk', 'Eggs',
  'Margarine', 'Beef', 'Washing powder', 'Tissue', 'Juice', 'Flour', 'Tea',
  'Noodles', 'Beans', 'Soap', 'Diapers', 'Biscuits', 'Beer',
];

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    _query.text = q;
    _query.selection = TextSelection.collapsed(offset: q.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final q = _query.text.trim();
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.only(top: wide ? 36 : 20, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Who has it cheapest?',
                        style: display(context, size: wide ? 46 : 34),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: TextField(
                        controller: _query,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search an item, like cooking oil',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: p.inkSoft,
                          ),
                          suffixIcon: q.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () => _setQuery(''),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (q.isEmpty) ..._browse(context, s) else ..._results(context, s, q),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ------------------------------------------------------------ no query

  List<Widget> _browse(BuildContext context, AppState s) {
    final p = Palette.of(context);
    final items = s.liveItems;

    // Staples on special, the ones stocked by the most shops first.
    final staples = <(String, int, int)>[];
    for (final name in _staples) {
      final hits = s.search(name, within: items);
      if (hits.isEmpty) continue;
      staples.add((
        name,
        hits.map((i) => i.retailerId).toSet().length,
        hits.length,
      ));
    }
    staples.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : b.$3.compareTo(a.$3);
    });

    final groups = s.crossShopGroups;

    return [
      if (staples.isNotEmpty)
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On special this week',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.inkSoft,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      if (staples.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: SizedBox(
              height: 44,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: staples.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final (name, shops, count) = staples[i];
                      return Semantics(
                        button: true,
                        label:
                            '$name, $count price${count == 1 ? '' : 's'} at $shops shop${shops == 1 ? '' : 's'}',
                        excludeSemantics: true,
                        child: Material(
                          color: p.surface,
                          shape: StadiumBorder(side: BorderSide(color: p.line)),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _setQuery(name),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: p.ink,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$shops shop${shops == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: p.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SectionTitle(
              'Same item, more than one shop',
              detail: groups.isEmpty
                  ? null
                  : 'Matched by name and pack size. Biggest price gap first.',
            ),
          ),
        ),
      ),
      if (groups.isEmpty)
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  items.isEmpty
                      ? 'No prices have been read from the leaflets yet.'
                      : 'No identical item is in more than one shop\'s '
                            'leaflet this week. Search above to line up '
                            'similar items by price per kg or litre.',
                  style: TextStyle(fontSize: 15, color: p.inkSoft, height: 1.4),
                ),
              ),
            ),
          ),
        )
      else
        SliverToBoxAdapter(
          child: ContentWidth(
            child: _CardGrid(
              children: [for (final g in groups) _GroupCard(group: g)],
            ),
          ),
        ),
    ];
  }

  // ----------------------------------------------------------- with query

  List<Widget> _results(BuildContext context, AppState s, String q) {
    final p = Palette.of(context);
    final hits = s.search(q);
    if (hits.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nothing called "$q" is on special',
                    style: display(context, size: 20, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try a shorter word, or watch it and it will show up on '
                    'your watchlist when a leaflet has it.',
                    style: TextStyle(fontSize: 15, color: p.inkSoft),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: s.isWatched(q)
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await s.watch(q);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Watching "$q".')),
                            );
                          },
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(s.isWatched(q) ? 'Watching' : 'Watch "$q"'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    // search() puts items with a known pack size first, by unit price.
    final unit = hits.first.unitPrice != null;
    double value(DealItem i) => unit ? (i.unitPrice ?? i.price) : i.price;
    final best = hits.first;

    // Best option per shop, cheapest shop first.
    final perShop = <String, DealItem>{};
    for (final i in hits) {
      perShop.putIfAbsent(i.retailerId, () => i);
    }

    String? note(DealItem i) {
      if (i.id == best.id) return unit ? 'Lowest ${i.unitPriceLabel}' : null;
      if (unit && i.unitPrice == null) return 'Pack size not read';
      final diff = value(i) - value(best);
      if (diff < 0.005) return 'Same price';
      final amount = formatPrice(double.parse(diff.toStringAsFixed(2)));
      return unit ? '$amount more ${i.unitPriceLabel}' : '$amount more';
    }

    return [
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionTitle(
              '${hits.length} price${hits.length == 1 ? '' : 's'} for "$q"',
              detail: unit
                  ? 'Lined up by price ${best.unitPriceLabel}, so different pack sizes compare fairly.'
                  : 'Lined up by shelf price. Pack sizes could not be read, so check them.',
            ),
          ),
        ),
      ),
      if (perShop.length > 1)
        SliverToBoxAdapter(
          child: ContentWidth(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Best at each shop',
                    style: display(context, size: 17, weight: FontWeight.w700),
                  ),
                  for (final i in perShop.values)
                    PriceRow(
                      item: i,
                      best: i.id == best.id,
                      note: note(i),
                      onTap: () => showItemSheet(context, i),
                    ),
                ],
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: ContentWidth(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                for (var k = 0; k < hits.length; k++) ...[
                  if (k > 0) const Divider(),
                  PriceRow(
                    item: hits[k],
                    best: hits[k].id == best.id,
                    note: perShop.length > 1 ? null : note(hits[k]),
                    onTap: () => showItemSheet(context, hits[k]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

/// One or two columns of cards depending on width.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final two = c.maxWidth >= 760;
        if (!two) {
          return Column(
            children: [
              for (final w in children)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
            ],
          );
        }
        final left = <Widget>[], right = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          (i.isEven ? left : right).add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: children[i],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: left)),
            const SizedBox(width: 12),
            Expanded(child: Column(children: right)),
          ],
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final PriceGroup group;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final best = group.best;
    final unit = group.comparesUnitPrice;
    final gap = group.valueOf(group.items.last) - group.valueOf(best);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            best.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: display(context, size: 17, weight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            gap < 0.005
                ? 'Same price at ${group.shopCount} shops'
                : '${best.retailer.name} is ${formatPrice(double.parse(gap.toStringAsFixed(2)))} cheaper${unit ? ' ${best.unitPriceLabel}' : ''}',
            style: TextStyle(fontSize: 13.5, color: p.inkSoft),
          ),
          for (var k = 0; k < group.items.length; k++) ...[
            if (k > 0) const Divider(),
            PriceRow(
              item: group.items[k],
              best: k == 0,
              onTap: () => showItemSheet(context, group.items[k]),
            ),
          ],
        ],
      ),
    );
  }
}
