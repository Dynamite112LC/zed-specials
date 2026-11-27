import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

/// Shelf-label price: the one loud element in the app.
/// The "K" and the ngwee sit raised and small, the way leaflets print them.
class PriceTag extends StatelessWidget {
  const PriceTag(
    this.price, {
    super.key,
    this.size = 24,
    this.perKg = false,
    this.plain = false,
  });

  final double price;

  /// Font size of the kwacha digits.
  final double size;
  final bool perKg;

  /// Plain tags drop the yellow label: used for the dearer options in a
  /// comparison so only the best price shouts.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fg = plain ? p.ink : p.onTag;
    final whole = price.floor();
    final ngwee = ((price - whole) * 100).round();
    final digits = formatPrice(whole.toDouble()).substring(1);
    final small = display(context, size: size * 0.5, color: fg, height: 1);

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: size * 0.08, right: 1),
          child: Text('K', style: small),
        ),
        Text(digits, style: display(context, size: size, color: fg, height: 1)),
        if (ngwee > 0)
          Padding(
            padding: EdgeInsets.only(top: size * 0.08, left: 1),
            child: Text(ngwee.toString().padLeft(2, '0'), style: small),
          ),
        if (perKg)
          Padding(
            padding: EdgeInsets.only(top: size * 0.46, left: 3),
            child: Text(
              '/kg',
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
                color: fg,
                height: 1,
              ),
            ),
          ),
      ],
    );

    final semantics =
        '${formatPrice(price)}${perKg ? ' per kilogram' : ''}';
    if (plain) {
      return Semantics(label: semantics, excludeSemantics: true, child: label);
    }
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.tag,
          shape: _TagShape(cut: size * 0.34, radius: size * 0.2),
          shadows: [
            BoxShadow(
              color: const Color(0xFF14180F).withValues(alpha: 0.18),
              blurRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            size * 0.42,
            size * 0.2,
            size * 0.36,
            size * 0.2,
          ),
          child: label,
        ),
      ),
    );
  }
}

/// A label with its top-left corner clipped, like a swing tag.
class _TagShape extends ShapeBorder {
  const _TagShape({required this.cut, required this.radius});

  final double cut;
  final double radius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = radius;
    return Path()
      ..moveTo(rect.left + cut, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r))
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(
        Offset(rect.right - r, rect.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(
        Offset(rect.left, rect.bottom - r),
        radius: Radius.circular(r),
      )
      ..lineTo(rect.left, rect.top + cut)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => _TagShape(cut: cut * t, radius: radius * t);
}

/// Brand dot plus shop name.
class RetailerMark extends StatelessWidget {
  const RetailerMark(this.retailer, {super.key, this.fontSize = 12.5});

  final Retailer retailer;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: fontSize * 0.72,
          height: fontSize * 0.72,
          decoration: BoxDecoration(
            color: Color(0xFF000000 | retailer.color),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        SizedBox(width: fontSize * 0.45),
        Flexible(
          child: Text(
            retailer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: p.inkSoft,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// An image from the feed, with a quiet placeholder while loading or missing.
class FeedImage extends StatelessWidget {
  const FeedImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.semanticLabel,
    this.spinner = false,
  });

  final String? path;
  final BoxFit fit;
  final Alignment alignment;
  final String? semanticLabel;

  /// Show a progress ring while loading (for full pages); otherwise a
  /// quiet tinted block holds the space.
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final placeholder = ColoredBox(
      color: p.sunken,
      child: Center(
        child: Icon(Icons.local_offer_outlined, color: p.line, size: 28),
      ),
    );
    final path = this.path;
    if (path == null) return placeholder;
    return Image(
      image: AppScope.read(context).image(path),
      fit: fit,
      alignment: alignment,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.center,
          children: [
            if (frame == null)
              spinner
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFFFFD21F),
                      ),
                    )
                  : Positioned.fill(child: ColoredBox(color: p.sunken)),
            AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              child: child,
            ),
          ],
        );
      },
    );
  }
}

/// A product with its price, as a grid tile.
class DealTile extends StatelessWidget {
  const DealTile(this.item, {super.key, required this.onTap});

  final DealItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = item.sizeLabel;
    return Semantics(
      button: true,
      label:
          '${item.name}, ${formatPrice(item.price)}'
          '${item.perKg ? ' per kilogram' : ''} at ${item.retailer.name}',
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    FeedImage(item.crop),
                    Positioned(
                      left: 10,
                      bottom: -14,
                      child: PriceTag(
                        item.price,
                        size: 26,
                        perKg: item.perKg,
                      ),
                    ),
                    if (item.save != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _SaveBadge(item.save!),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 38,
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: p.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: RetailerMark(item.retailer)),
                        if (size != null)
                          Text(
                            size,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: p.inkSoft,
                              height: 1.1,
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
      ),
    );
  }
}

class _SaveBadge extends StatelessWidget {
  const _SaveBadge(this.save);

  final double save;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Save ${formatPrice(save)}',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: p.paper,
          height: 1.1,
        ),
      ),
    );
  }
}

/// A catalogue shown as a physical leaflet with its time left.
class LeafletCard extends StatelessWidget {
  const LeafletCard(
    this.catalogue, {
    super.key,
    required this.onTap,
    this.width = 156,
    this.tilt = 0,
  });

  final Catalogue catalogue;
  final VoidCallback onTap;
  final double width;

  /// Rotation in radians; alternating leaflets lean slightly on the shelf.
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final state = AppScope.of(context);
    final now = state.now;
    final days = catalogue.daysLeft(now);
    final urgent = days != null && days <= 1;
    final isNew = state.isNew(catalogue);

    // Fraction of the validity period already used up.
    double? elapsed;
    final from = catalogue.validFrom, to = catalogue.validTo;
    if (from != null && to != null) {
      final total = to.difference(from).inDays + 1;
      final used = now.difference(from).inHours / 24;
      elapsed = total <= 0 ? 1 : (used / total).clamp(0.04, 1.0);
    }

    return Semantics(
      button: true,
      label:
          '${catalogue.retailer.name}, ${catalogue.title}. '
          '${endsLabel(catalogue, now)}.${isNew ? ' New.' : ''}',
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.rotate(
                  angle: tilt,
                  child: Hero(
                    tag: 'leaflet-${catalogue.id}',
                    child: AspectRatio(
                      aspectRatio: 0.7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: p.ink.withValues(alpha: 0.16),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              FeedImage(
                                catalogue.cover,
                                alignment: Alignment.topCenter,
                              ),
                              if (isNew)
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: p.tag,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'New',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: p.onTag,
                                        height: 1.1,
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
                ),
                const SizedBox(height: 14),
                RetailerMark(catalogue.retailer),
                const SizedBox(height: 4),
                Text(
                  catalogue.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: display(
                    context,
                    size: 16.5,
                    weight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                if (elapsed != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: elapsed,
                      minHeight: 4,
                      backgroundColor: p.line,
                      color: urgent ? p.urgent : p.green,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  endsLabel(catalogue, now),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: urgent ? FontWeight.w700 : FontWeight.w500,
                    color: urgent ? p.urgent : p.inkSoft,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section heading used across screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: display(context, size: 22, weight: FontWeight.w700),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail!, style: TextStyle(fontSize: 14, color: p.inkSoft)),
        ],
      ],
    );
  }
}

/// Keeps content readable on wide screens.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.padding = 20});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padding),
        // Fill the column so content starts at its left edge.
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}
