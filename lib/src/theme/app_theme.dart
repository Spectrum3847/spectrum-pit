import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'pit_palette.dart';

TextStyle pitCodeStyle(BuildContext context, {Color? color}) {
  return GoogleFonts.ibmPlexMono(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.26,
    color: color,
  );
}

const _smShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(PitPalette.radiusSm)),
);
const _lgShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(PitPalette.radiusLg)),
);

const _minTarget = Size(64, 48);

final _filledButtonTheme = FilledButtonThemeData(
  style: FilledButton.styleFrom(shape: _smShape, minimumSize: _minTarget),
);
const _segmentedButtonTheme = SegmentedButtonThemeData(
  style: ButtonStyle(shape: WidgetStatePropertyAll(_smShape)),
);

TextTheme _textThemeFor(TextTheme base, Color ink) {
  final title = GoogleFonts.ibmPlexSans(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: ink,
  );
  return GoogleFonts.ibmPlexSansTextTheme(base).copyWith(
    displayLarge: title,
    displayMedium: title,
    displaySmall: title,
    headlineLarge: title,
    headlineMedium: title,
    headlineSmall: title,
    titleLarge: title,
    titleMedium: title,
    bodyLarge: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: ink,
    ),
    bodyMedium: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: ink,
    ),
    labelLarge: GoogleFonts.ibmPlexSans(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.13,
      color: ink,
    ),
  );
}

ThemeData _themeFrom({
  required Brightness brightness,
  required Color canvas,
  required Color surface,
  required Color surfaceStrong,
  required Color outline,
  required Color ink,
  required Color inkMuted,
  required Color accentPrimary,
  required Color accentLifted,
  required Color error,
  required Color onError,
}) {
  final isDark = brightness == Brightness.dark;
  final base = isDark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final textTheme = _textThemeFor(base.textTheme, ink);

  final colorScheme =
      (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        brightness: brightness,
        primary: accentPrimary,
        onPrimary: Colors.white,
        secondary: surfaceStrong,
        onSecondary: ink,
        surface: canvas,
        onSurface: ink,
        onSurfaceVariant: inkMuted,
        outline: outline,
        error: error,
        onError: onError,

        surfaceTint: Colors.transparent,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    textTheme: textTheme,
    fontFamily: GoogleFonts.ibmPlexSans().fontFamily,
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(PitPalette.radiusSm),
        ),
        side: BorderSide(color: outline),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.transparent,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(PitPalette.radiusSm),
        ),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(PitPalette.radiusSm),
        ),
        borderSide: BorderSide(color: outline),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(PitPalette.radiusSm),
        ),
        borderSide: BorderSide(color: accentPrimary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceStrong,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: _lgShape,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surfaceStrong,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(PitPalette.radiusLg),
        ),
        side: BorderSide(color: outline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceStrong,
      selectedColor: accentPrimary,
      side: BorderSide(color: outline),
      shape: _smShape,
      labelStyle: textTheme.labelLarge,
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accentPrimary.withValues(alpha: 0.18),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? accentLifted
              : inkMuted,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelLarge?.copyWith(
          color: selected ? accentLifted : inkMuted,
        );
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? accentPrimary : inkMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? accentPrimary.withValues(alpha: 0.4)
            : surfaceStrong;
      }),
      trackOutlineColor: WidgetStatePropertyAll(outline),
    ),
    filledButtonTheme: _filledButtonTheme,

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _smShape,
        minimumSize: _minTarget,
        foregroundColor: ink,
        side: BorderSide(color: outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: _smShape,
        minimumSize: _minTarget,
        foregroundColor: ink,
      ),
    ),
    segmentedButtonTheme: _segmentedButtonTheme,
  );
}

ThemeData buildDarkAppTheme() {
  return _themeFrom(
    brightness: Brightness.dark,
    canvas: PitPalette.caseBlack,
    surface: PitPalette.caseSurface,
    surfaceStrong: PitPalette.caseSurfaceStrong,
    outline: PitPalette.outline,
    ink: PitPalette.ink,
    inkMuted: PitPalette.inkMuted,
    accentPrimary: PitPalette.violetCore,
    accentLifted: PitPalette.violetLifted,
    error: PitPalette.statusOverdue,
    onError: PitPalette.caseBlack,
  );
}

ThemeData buildAppTheme() {
  return _themeFrom(
    brightness: Brightness.light,
    canvas: PitPalette.lightCanvas,
    surface: PitPalette.lightSurface,
    surfaceStrong: PitPalette.lightSurfaceStrong,
    outline: PitPalette.lightOutline,
    ink: PitPalette.lightInk,
    inkMuted: PitPalette.lightInkMuted,
    accentPrimary: PitPalette.violetDeep,
    accentLifted: PitPalette.violetDeep,
    error: PitPalette.lightStatusOverdue,
    onError: Colors.white,
  );
}
