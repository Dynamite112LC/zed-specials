import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalogue_viewer.dart';
import 'item_zoom.dart';

/// A short phrase to watch for, taken from an item's name:
/// "Ultra Fat Free Spread 500g Each" becomes "ultra fat free".
String watchTermFor(DealItem item) {
  const noise = {
    'each',
    'assorted',
    'all',
    'variants',
    'per',
    'kg',
    'pack',
    'or',
    'and',
    'with',
    'the',
    'in',
    'selected',
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
    builder: (_) =>
        _ItemSheet(item: item, fromViewer: fromViewer, hostContext: context),
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
                // Tap the picture to see the item as printed, enlarged.
                Semantics(
                  button: true,
                  label: 'Enlarge to check against the leaflet',
                  child: InkWell(
                    onTap: () => openItemZoom(hostContext, item),
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 112,
                            height: 112,
                            child: FeedImage(item.crop),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: p.ink.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.zoom_in_rounded,
                              size: 18,
                              color: p.paper,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                PriceTag(item.price, size: 44, unit: item.priceUnit),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.cardPrice != null)
                        Text(
                          cardNote(item),
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
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

            const SizedBox(height: 24),
            _PriceHistory(item),

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
                        fromViewer
                            ? 'Back to the page'
                            : 'See it on the leaflet',
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
                            SnackBar(
                              content: Text('Stopped watching "$term".'),
                            ),
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
              item.corrected
                  ? 'This reading was checked against the leaflet and '
                        'corrected by a person.'
                  : item.inDoubt
                  ? 'This page was read twice and the other reading gave '
                        '${formatPrice(item.otherPrice!)}. Tap the picture '
                        'to check which price is printed.'
                  : item.agreed
                  ? 'This page was read twice, in two different ways, and '
                        'both readings gave this price. Tap the picture to '
                        'see it on the leaflet.'
                  : 'Prices are read from the leaflet automatically and can '
                        'be misread. Tap the picture to check this one '
                        'against the leaflet.',
              style: TextStyle(fontSize: 12.5, color: p.inkSoft, height: 1.4),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => showCorrectionSheet(hostContext, item),
                child: const Text('Something wrong? Fix this reading'),
              ),
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

/// What the item cost in earlier leaflets, drawn as bars from zero so the
/// lengths compare honestly.
class _PriceHistory extends StatelessWidget {
  // Past prices are the ones printed for everyone, so today's is too.
  _PriceHistory(DealItem item) : item = item.withoutCard();

  final DealItem item;

  static const _shown = 6;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = AppScope.of(context).now;
    final past = item.history.reversed.toList();
    final heading = Text(
      'Price history',
      style: display(context, size: 17, weight: FontWeight.w700),
    );

    if (past.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 6),
          Text(
            'No earlier price recorded for this item yet. Each new leaflet '
            'adds to the record.',
            style: TextStyle(fontSize: 14, color: p.inkSoft, height: 1.4),
          ),
        ],
      );
    }

    final shown = past.take(_shown).toList();
    var top = item.price;
    for (final h in shown) {
      if (h.price > top) top = h.price;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        const SizedBox(height: 6),
        Text(
          _verdict(past, now),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: p.ink,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        _HistoryBar(
          label: '${item.retailer.name}, now',
          price: item.price,
          share: item.price / top,
          current: true,
        ),
        for (final h in shown)
          _HistoryBar(
            label: '${h.retailer.name}, ${rangeLabel(h.from, h.to, now)}',
            price: h.price,
            share: h.price / top,
          ),
        if (past.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              past.length - _shown == 1
                  ? '1 older price is not shown.'
                  : '${past.length - _shown} older prices are not shown.',
              style: TextStyle(fontSize: 12.5, color: p.inkSoft),
            ),
          ),
      ],
    );
  }

  String _verdict(List<PricePoint> past, DateTime now) {
    final low = past.reduce((a, b) => b.price < a.price ? b : a);
    final last = item.lastPriceHere;
    final parts = <String>[];
    if (item.price < low.price - 0.005) {
      parts.add('This is the lowest price recorded for it.');
    } else if (low.price < item.price - 0.005) {
      parts.add(
        'It has been lower: ${formatPrice(low.price)} at '
        '${low.retailer.name}, ${rangeLabel(low.from, low.to, now)}.',
      );
    } else {
      parts.add('This matches the lowest price recorded for it.');
    }
    if (last != null) {
      final d = item.price - last.price;
      final amount = formatPrice(double.parse(d.abs().toStringAsFixed(2)));
      final shop = item.retailer.name;
      // Skip when the first sentence already made this comparison.
      final least = last.price * 0.01 > 0.05 ? last.price * 0.01 : 0.05;
      if (d <= -least) {
        parts.add("$amount less than in $shop's last leaflet.");
      } else if (d >= least && !identical(last, low)) {
        parts.add("$amount more than in $shop's last leaflet.");
      }
    }
    return parts.join(' ');
  }
}

class _HistoryBar extends StatelessWidget {
  const _HistoryBar({
    required this.label,
    required this.price,
    required this.share,
    this.current = false,
  });

  final String label;
  final double price;

  /// Bar length as a fraction of the row, 0..1.
  final double share;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: '$label, ${formatPrice(price)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                      color: current ? p.ink : p.inkSoft,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatPrice(price),
                  style: display(
                    context,
                    size: 15,
                    weight: FontWeight.w700,
                    color: current ? p.ink : p.inkSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            FractionallySizedBox(
              widthFactor: share.clamp(0.02, 1.0),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: current ? p.tag : p.inkSoft.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
