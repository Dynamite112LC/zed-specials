import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_sheet.dart';

/// Opens [catalogue] full screen at [page] (1-based).
void openCatalogue(BuildContext context, Catalogue catalogue, {int page = 1}) {
  AppScope.read(context).markSeen(catalogue);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CatalogueViewer(catalogue: catalogue, initialPage: page),
    ),
  );
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

Future<void> openOnShopSite(BuildContext context, String url) async {
  final ok = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open the shop's site.")),
    );
  }
}

class CatalogueViewer extends StatefulWidget {
  const CatalogueViewer({
    super.key,
    required this.catalogue,
    this.initialPage = 1,
  });

  final Catalogue catalogue;
  final int initialPage;

  @override
  State<CatalogueViewer> createState() => _CatalogueViewerState();
}

class _CatalogueViewerState extends State<CatalogueViewer> {
  late int _page = widget.initialPage.clamp(
    1,
    widget.catalogue.pages.isEmpty ? 1 : widget.catalogue.pages.length,
  );
  late final PageController _pages = PageController(initialPage: _page - 1);
  final _zoom = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.02;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _page + delta;
    if (target < 1 || target > widget.catalogue.pages.length) return;
    _zoom.value = Matrix4.identity();
    _pages.animateToPage(
      target - 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleZoom(TapDownDetails d) {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
    } else {
      final pos = d.localPosition;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-pos.dx * 1.5, -pos.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.catalogue;
    final p = Palette.of(context);
    final s = AppScope.of(context);
    const backdrop = Color(0xFF07100C);
    const onBackdrop = Color(0xFFEAF2ED);
    final pageItems = s.itemsOnPage(c.id, _page)
      ..sort((a, b) => a.price.compareTo(b.price));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: backdrop,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: Focus(
            autofocus: true,
            child: SafeArea(
              child: Column(
                children: [
                  // ------------------------------------------------ top bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          color: onBackdrop,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: display(
                                  context,
                                  size: 18,
                                  weight: FontWeight.w700,
                                  color: onBackdrop,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${c.retailer.name}, ${_lowerFirst(endsLabel(c, s.now))}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF9DB1A6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: "Open on ${c.retailer.name}'s site",
                          color: onBackdrop,
                          onPressed: () => openOnShopSite(context, c.sourceUrl),
                          icon: const Icon(Icons.open_in_new_rounded),
                        ),
                      ],
                    ),
                  ),

                  // -------------------------------------------------- pages
                  Expanded(
                    child: c.pages.isEmpty
                        ? _NoPages(catalogue: c)
                        : PageView.builder(
                            controller: _pages,
                            physics: _zoomed
                                ? const NeverScrollableScrollPhysics()
                                : const PageScrollPhysics(),
                            itemCount: c.pages.length,
                            onPageChanged: (i) {
                              _zoom.value = Matrix4.identity();
                              setState(() => _page = i + 1);
                            },
                            itemBuilder: (context, i) {
                              final current = i == _page - 1;
                              Widget image = FeedImage(
                                c.pages[i].image,
                                fit: BoxFit.contain,
                                spinner: true,
                                semanticLabel:
                                    '${c.retailer.name} ${c.title}, page ${i + 1}',
                              );
                              if (i == 0) {
                                image = Hero(
                                  tag: 'leaflet-${c.id}',
                                  child: image,
                                );
                              }
                              return GestureDetector(
                                onDoubleTapDown: current ? _toggleZoom : null,
                                onDoubleTap: () {},
                                child: InteractiveViewer(
                                  transformationController: current
                                      ? _zoom
                                      : null,
                                  minScale: 1,
                                  maxScale: 6,
                                  child: Center(child: image),
                                ),
                              );
                            },
                          ),
                  ),

                  // --------------------------------------------- bottom bar
                  if (c.pages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Previous page',
                            color: onBackdrop,
                            disabledColor: const Color(0xFF3A4A42),
                            onPressed: _page > 1 ? () => _go(-1) : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Page $_page of ${c.pages.length}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: onBackdrop,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next page',
                            color: onBackdrop,
                            disabledColor: const Color(0xFF3A4A42),
                            onPressed: _page < c.pages.length
                                ? () => _go(1)
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                          const Spacer(),
                          if (pageItems.isNotEmpty)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: p.tag,
                                foregroundColor: p.onTag,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                              ),
                              onPressed: () =>
                                  _showPagePrices(context, pageItems),
                              icon: const Icon(Icons.sell_outlined, size: 18),
                              label: Text(
                                MediaQuery.sizeOf(context).width < 480
                                    ? '${pageItems.length} price${pageItems.length == 1 ? '' : 's'}'
                                    : '${pageItems.length} price${pageItems.length == 1 ? '' : 's'} on this page',
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPagePrices(BuildContext context, List<DealItem> items) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView.separated(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: items.length + 1,
          separatorBuilder: (_, i) =>
              i == 0 ? const SizedBox(height: 12) : const Divider(),
          itemBuilder: (context, i) {
            if (i == 0) {
              return SectionTitle(
                'Prices on page $_page',
                detail: 'Read automatically. Check against the page.',
              );
            }
            final item = items[i - 1];
            return PriceRow(
              item: item,
              best: false,
              showShop: false,
              onTap: () {
                Navigator.of(sheetContext).pop();
                showItemSheet(this.context, item, fromViewer: true);
              },
            );
          },
        ),
      ),
    );
  }
}

class _NoPages extends StatelessWidget {
  const _NoPages({required this.catalogue});

  final Catalogue catalogue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "This leaflet's pages couldn't be saved.",
              textAlign: TextAlign.center,
              style: display(
                context,
                size: 22,
                weight: FontWeight.w700,
                color: const Color(0xFFEAF2ED),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Palette.of(context).tag,
                foregroundColor: Palette.of(context).onTag,
              ),
              onPressed: () => openOnShopSite(context, catalogue.sourceUrl),
              child: Text("Open on ${catalogue.retailer.name}'s site"),
            ),
          ],
        ),
      ),
    );
  }
}

/// One item in a list of prices: picture, name, shop and price.
class PriceRow extends StatelessWidget {
  const PriceRow({
    super.key,
    required this.item,
    required this.best,
    required this.onTap,
    this.showShop = true,
    this.note,
  });

  final DealItem item;

  /// The cheapest option in its list gets the yellow tag.
  final bool best;
  final bool showShop;
  final VoidCallback onTap;

  /// Extra line under the name, e.g. "K4 more per kg".
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final unit = item.unitPrice;
    final size = item.sizeLabel;
    final detail = [
      ?size,
      if (unit != null && !item.perKg)
        '${formatPrice(double.parse(unit.toStringAsFixed(2)))} ${item.unitPriceLabel}',
    ].join(', ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: FeedImage(item.crop),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showShop) ...[
                    RetailerMark(item.retailer),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                      height: 1.25,
                    ),
                  ),
                  if (detail.isNotEmpty || note != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      [if (detail.isNotEmpty) detail, ?note].join('. '),
                      style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            PriceTag(item.price, size: 22, perKg: item.perKg, plain: !best),
          ],
        ),
      ),
    );
  }
}
