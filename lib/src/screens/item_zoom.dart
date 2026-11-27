import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalogue_viewer.dart';

/// Opens the part of the leaflet an item was read from, enlarged, so the
/// printed price and description can be checked against the reading.
void openItemZoom(BuildContext context, DealItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _ItemZoom(item: item),
    ),
  );
}

/// What reading the page twice came to: the same price, or two.
class _TwoReadings extends StatelessWidget {
  const _TwoReadings({required this.item});

  final DealItem item;

  @override
  Widget build(BuildContext context) {
    final doubt = item.inDoubt;
    final colour = doubt ? const Color(0xFFF2C14E) : const Color(0xFF8FD3A8);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          doubt ? Icons.help_outline_rounded : Icons.done_all_rounded,
          size: 18,
          color: colour,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            doubt
                ? 'Another reading of this page gave '
                      '${formatPrice(item.otherPrice!)}. Check which one is '
                      'printed.'
                : 'Two separate readings of this page gave this price.',
            style: TextStyle(fontSize: 13, color: colour, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _ItemZoom extends StatelessWidget {
  const _ItemZoom({required this.item});

  final DealItem item;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // The item as it stands now: it may have been corrected a moment ago.
    final current = s.feed.items.where((i) => i.id == item.id).firstOrNull;
    final shown = current ?? item;
    final catalogue = s.catalogue(item.catalogueId);
    final pagePath =
        catalogue != null &&
            item.page >= 1 &&
            item.page <= catalogue.pages.length
        ? catalogue.pages[item.page - 1].image
        : null;
    final box = item.box;
    const ink = Color(0xFFF3F6F4);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F0D),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: ink),
                  ),
                  Expanded(
                    child: Text(
                      'As printed on the leaflet',
                      style: display(
                        context,
                        size: 17,
                        weight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Center(
                  child: pagePath == null || box == null || box.length != 4
                      // Older feeds do not say where the item is: show the
                      // small picture rather than nothing.
                      ? FeedImage(item.crop, fit: BoxFit.contain, spinner: true)
                      : _PageRegion(image: s.image(pagePath), box: box),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFF14201A),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current == null
                        ? 'This reading was removed.'
                        : shown.corrected
                        ? 'Corrected to'
                        : 'Read as',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9DB1A6),
                    ),
                  ),
                  if (current != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            shown.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: ink,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        PriceTag(shown.price, size: 24, unit: shown.priceUnit),
                      ],
                    ),
                    if (shown.cardPrice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          shown.cardApplied
                              ? 'Smart Shopper price. '
                                    '${formatPrice(shown.shelfPrice!)} '
                                    'without the card.'
                              : '${formatPrice(shown.cardPrice!)} with a '
                                    'Smart Shopper card.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFC9D6CE),
                            height: 1.35,
                          ),
                        ),
                      ),
                    if (shown.inDoubt || (shown.agreed && !shown.corrected))
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _TwoReadings(item: shown),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (current != null)
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                showCorrectionSheet(context, shown),
                            child: const Text('Fix this reading'),
                          ),
                        ),
                      if (current != null && catalogue != null)
                        const SizedBox(width: 10),
                      if (catalogue != null && catalogue.pages.isNotEmpty)
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ink,
                              side: const BorderSide(color: Color(0xFF3A5145)),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              openCatalogue(
                                context,
                                catalogue,
                                page: item.page,
                              );
                            },
                            child: const Text('Whole page'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One rectangle of a page image, scaled to fit. [box] is left, top, width
/// and height as fractions of the page.
class _PageRegion extends StatelessWidget {
  const _PageRegion({required this.image, required this.box});

  final ImageProvider image;
  final List<double> box;

  @override
  Widget build(BuildContext context) {
    // A little of the surroundings helps to see which item this is.
    const margin = 0.12;
    final w = (box[2] * (1 + 2 * margin)).clamp(0.02, 1.0);
    final h = (box[3] * (1 + 2 * margin)).clamp(0.02, 1.0);
    final x = (box[0] - box[2] * margin).clamp(0.0, 1.0 - w);
    final y = (box[1] - box[3] * margin).clamp(0.0, 1.0 - h);
    // Align picks which part of the child shows: -1 is its start, 1 its end.
    final alignment = Alignment(
      w >= 1 ? 0 : -1 + 2 * x / (1 - w),
      h >= 1 ? 0 : -1 + 2 * y / (1 - h),
    );
    return FittedBox(
      fit: BoxFit.contain,
      child: ClipRect(
        child: Align(
          alignment: alignment,
          widthFactor: w,
          heightFactor: h,
          child: Image(
            image: image,
            filterQuality: FilterQuality.high,
            semanticLabel: 'The item as printed on the leaflet',
            frameBuilder: (context, child, frame, sync) =>
                frame == null && !sync
                ? const SizedBox(
                    width: 300,
                    height: 300,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFFFFD21F),
                      ),
                    ),
                  )
                : child,
            errorBuilder: (_, _, _) => const SizedBox(
              width: 300,
              height: 200,
              child: Center(
                child: Text(
                  "Couldn't load the leaflet page.\nCheck your connection.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFF3F6F4), fontSize: 15),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the shopper put a wrong reading right: the price, the name, or
/// that it is not a product at all.
void showCorrectionSheet(BuildContext context, DealItem item) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    // The reading being fixed is the price printed for everyone.
    builder: (_) =>
        _CorrectionSheet(item: item.withoutCard(), hostContext: context),
  );
}

class _CorrectionSheet extends StatefulWidget {
  const _CorrectionSheet({required this.item, required this.hostContext});

  final DealItem item;
  final BuildContext hostContext;

  @override
  State<_CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends State<_CorrectionSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _price = TextEditingController(
    text: widget.item.price == widget.item.price.roundToDouble()
        ? widget.item.price.toStringAsFixed(0)
        : widget.item.price.toStringAsFixed(2),
  );
  bool _notAProduct = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save({required bool send}) async {
    final s = AppScope.read(context);
    final item = widget.item;
    // A correction is always against what the feed builder read, so one
    // made on top of an earlier correction still finds its item.
    final read = s.asPublished(item);

    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (!_notAProduct) {
      if (price == null || price <= 0 || price > 1000000) {
        setState(() => _error = 'Enter the price as a number, like 149.99.');
        return;
      }
      if (name.isEmpty) {
        setState(() => _error = 'Enter the name as it is printed.');
        return;
      }
      if (name == item.name && (price - item.price).abs() < 0.005) {
        setState(() => _error = 'Change the price or the name first.');
        return;
      }
    }
    final correction = Correction(
      leaflet: read.catalogueId,
      page: read.page,
      readName: read.name,
      readPrice: read.price,
      name: _notAProduct ? null : name,
      price: _notAProduct ? null : price,
      remove: _notAProduct,
    );

    final messenger = ScaffoldMessenger.of(widget.hostContext);
    final navigator = Navigator.of(context);
    await s.correct(correction);
    navigator.pop();

    final url = send ? s.correctionReportUrl(correction) : null;
    if (url == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Corrected on this device.')),
      );
      return;
    }
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Corrected here. Submit the page that opened to fix the feed.'
              : "Corrected here. Couldn't open the page to send it.",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final canSend =
        s.correctionReportUrl(
          Correction(
            leaflet: widget.item.catalogueId,
            page: widget.item.page,
            readName: widget.item.name,
            readPrice: widget.item.price,
            remove: true,
          ),
        ) !=
        null;

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
            const SectionTitle('Fix this reading'),
            const SizedBox(height: 8),
            Text(
              'Type what the leaflet says. Your fix shows on this device '
              'straight away.',
              style: TextStyle(fontSize: 14.5, color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price,
              enabled: !_notAProduct,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Price in kwacha',
                prefixText: 'K ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: !_notAProduct,
              textCapitalization: TextCapitalization.words,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Name and size'),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notAProduct,
              onChanged: (v) => setState(() {
                _notAProduct = v;
                _error = null;
              }),
              title: const Text('This is not a product'),
              subtitle: const Text('Remove it from the list'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.urgent,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _save(send: canSend),
                child: Text(canSend ? 'Save and send to the feed' : 'Save'),
              ),
            ),
            if (canSend) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _save(send: false),
                  child: const Text('Save on this device only'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sending opens a filled-in report on GitHub for you to '
                'submit. The feed takes it up at its next update, and the '
                'fix then reaches every device and the price history.',
                style: TextStyle(fontSize: 12.5, color: p.inkSoft, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
