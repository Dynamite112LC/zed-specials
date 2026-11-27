import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colour tokens. The palette borrows from the shop floor: shelf-label yellow
/// for prices, bottle green for the app's own voice, and a cool till-paper
/// white behind everything. Retailer brand colours only appear as small marks.
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.paper,
    required this.surface,
    required this.sunken,
    required this.ink,
    required this.inkSoft,
    required this.line,
    required this.green,
    required this.onGreen,
    required this.tag,
    required this.onTag,
    required this.urgent,
  });

  /// Page background.
  final Color paper;

  /// Cards and sheets.
  final Color surface;

  /// Wells: image backdrops, input fields.
  final Color sunken;
  final Color ink;
  final Color inkSoft;
  final Color line;
  final Color green;
  final Color onGreen;

  /// Shelf-label yellow. Reserved for prices.
  final Color tag;
  final Color onTag;

  /// Ending today or tomorrow.
  final Color urgent;

  static const light = Palette(
    paper: Color(0xFFF1F5F2),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFE6ECE8),
    ink: Color(0xFF0F2A20),
    inkSoft: Color(0xFF52655C),
    line: Color(0xFFD5DED8),
    green: Color(0xFF0B6B43),
    onGreen: Color(0xFFFFFFFF),
    tag: Color(0xFFFFD21F),
    onTag: Color(0xFF14180F),
    urgent: Color(0xFFC81E2B),
  );

  static const dark = Palette(
    paper: Color(0xFF0B1611),
    surface: Color(0xFF13231C),
    sunken: Color(0xFF1B3027),
    ink: Color(0xFFEAF2ED),
    inkSoft: Color(0xFF9DB1A6),
    line: Color(0xFF28402F),
    green: Color(0xFF4CC58B),
    onGreen: Color(0xFF062015),
    tag: Color(0xFFFFD21F),
    onTag: Color(0xFF14180F),
    urgent: Color(0xFFFF6B6B),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) =>
      t < 0.5 || other is! Palette ? this : other;
}

/// Display face: used for headlines and every price.
TextStyle display(
  BuildContext context, {
  required double size,
  FontWeight weight = FontWeight.w800,
  Color? color,
  double height = 1.05,
}) => GoogleFonts.bricolageGrotesque(
  fontSize: size,
  fontWeight: weight,
  height: height,
  letterSpacing: size >= 28 ? -0.8 : -0.3,
  color: color ?? Palette.of(context).ink,
);

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme =
      ColorScheme.fromSeed(seedColor: p.green, brightness: brightness).copyWith(
        primary: p.green,
        onPrimary: p.onGreen,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.inkSoft,
        outline: p.line,
        outlineVariant: p.line,
        error: p.urgent,
        surfaceContainerHighest: p.sunken,
        surfaceContainerHigh: p.sunken,
        surfaceContainer: p.surface,
        surfaceContainerLow: p.surface,
        secondaryContainer: p.green.withValues(alpha: 0.14),
        onSecondaryContainer: p.ink,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.paper,
    extensions: [p],
    splashFactory: InkSparkle.splashFactory,
  );

  final text = GoogleFonts.figtreeTextTheme(
    base.textTheme,
  ).apply(bodyColor: p.ink, displayColor: p.ink);

  return base.copyWith(
    textTheme: text.copyWith(
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14.5, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.35,
        color: p.inkSoft,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.tag,
      height: 68,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? p.onTag : p.inkSoft,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => GoogleFonts.figtree(
          fontSize: 12.5,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.ink : p.inkSoft,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.tag,
      selectedIconTheme: IconThemeData(color: p.onTag),
      unselectedIconTheme: IconThemeData(color: p.inkSoft),
      selectedLabelTextStyle: GoogleFonts.figtree(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: p.ink,
      ),
      unselectedLabelTextStyle: GoogleFonts.figtree(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: p.inkSoft,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      selectedColor: p.ink,
      side: BorderSide(color: p.line),
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: GoogleFonts.figtree(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      secondaryLabelStyle: GoogleFonts.figtree(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: p.paper,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: GoogleFonts.figtree(color: p.inkSoft, fontSize: 15.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.green, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.paper,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.figtree(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.figtree(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: GoogleFonts.figtree(color: p.paper, fontSize: 14.5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
