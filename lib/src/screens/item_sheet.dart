import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalogue_viewer.dart';

/// A short phrase to watch for, taken from an item's name:
/// "Ultra Fat Free Spread 500g Each" becomes "ultra fat free".
String watchTermFor(DealItem item) {
  const noise = {
    'each', 'assorted', 'all', 'variants', 'per', 'kg', 'pack', 'or', 'and',
    'with', 'the', 'in', 'selected',
  };
  final words = item.name
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((w) => w.length > 1 && !noise.contains(w))
      .take(3)
      .toList();
  return words.join(' ');
}

void showItemSheet(
  BuildContext context,
  DealItem item, {
  bool fromViewer = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _ItemSheet(
      item: item,
      fromViewer: fromViewer,
      hostContext: context,
    ),
  );
}

class _ItemSheet extends StatelessWidget {
  const _ItemSheet({
    required this.item,
    required this.fromViewer,
    required this.hostContext,
  });

  final DealItem item;
  final bool fromViewer;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final catalogue = s.catalogue(item.catalogueId);
    final group = s.groupOf(item);
    final others = group?.items.where((i) => i.id != item.id).toList() ?? [];
    final unit = item.unitPrice;
    final term = watchTermFor(item);
    final watched = term.isNotEmpty && s.isWatched(term);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 112,
                    height: 112,
                    child: FeedImage(item.crop),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RetailerMark(item.retailer, fontSize: 13.5),
                      const SizedBox(height: 6),
                      Text(
                        item.name,
                        style: display(
                          context,
                          size: 21,
                          weight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PriceTag(item.price, size: 44, perKg: item.perKg),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (unit != null && !item.perKg)
                        Text(
                          'Works out to ${formatPrice(double.parse(unit.toStringAsFixed(2)))} ${item.unitPriceLabel}',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                      if (item.save != null)
                        Text(
                          'The leaflet says you save ${formatPrice(item.save!)}',
                          style: TextStyle(fontSize: 14, color: p.inkSoft),
                        ),
                      if (catalogue != null)
                        Text(
                          '${endsLabel(catalogue, s.now)}${catalogue.stores == null ? '' : '. ${catalogue.stores}'}',
                          style: TextStyle(fontSize: 14, color: p.inkSoft),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            if (others.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'The same item in other leaflets',
                style: display(context, size: 17, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              for (final other in others)
                PriceRow(
                  item: other,
                  best: group!.best.id == other.id,
                  note: _difference(group, item, other),
                  onTap: () {
                    Navigator.of(context).pop();
                    showItemSheet(hostContext, other, fromViewer: fromViewer);
                  },
                ),
            ],

            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (catalogue != null && catalogue.pages.isNotEmpty)
                  SizedBox(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (fromViewer) return;
                        openCatalogue(hostContext, catalogue, page: item.page);
                      },
                      child: Text(
                        fromViewer ? 'Back to the page' : 'See it on the leaflet',
                      ),
                    ),
                  ),
                if (term.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(hostContext);
                        if (watched) {
                          final existing = s.watchlist.firstWhere(
                            (w) => w.toLowerCase() == term,
                          );
                          await s.unwatch(existing);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Stopped watching "$term".')),
                          );
                        } else {
                          await s.watch(term);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Watching "$term".')),
                          );
                        }
                      },
                      icon: Icon(
                        watched
                            ? Icons.visibility_rounded
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      label: Text(watched ? 'Watching' : 'Watch this item'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Prices are read from the leaflet automatically and can be '
              'misread. Check the leaflet before you make the trip.',
              style: TextStyle(fontSize: 12.5, color: p.inkSoft, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  String? _difference(PriceGroup group, DealItem a, DealItem b) {
    final unit = group.comparesUnitPrice;
    final diff = group.valueOf(b) - group.valueOf(a);
    final suffix = unit ? ' ${a.unitPriceLabel}' : '';
    final amount = formatPrice(double.parse(diff.abs().toStringAsFixed(2)));
    if (diff.abs() < 0.005) return 'Same price$suffix';
    return diff > 0 ? '$amount more$suffix' : '$amount less$suffix';
  }
}
