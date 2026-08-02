import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/theme/pit_palette.dart';

void main() {
  // The Shadow Board theme resolves every dual-theme surface through the
  // PitPalette `*Of(context)` accessors so no raw light token leaks into the
  // dark theme (or vice versa). Asserting they resolve the right tokens per
  // brightness keeps that guarantee.
  group('theme-aware palette tokens', () {
    testWidgets('accessors resolve dark tokens in dark mode', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkAppTheme(),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(PitPalette.canvasOf(context), PitPalette.caseBlack);
      expect(PitPalette.surfaceOf(context), PitPalette.caseSurface);
      expect(PitPalette.surfaceStrongOf(context), PitPalette.caseSurfaceStrong);
      expect(PitPalette.outlineOf(context), PitPalette.outline);
      expect(PitPalette.inkOf(context), PitPalette.ink);
      expect(PitPalette.accentOf(context), PitPalette.violetLifted);
    });

    testWidgets('accessors resolve light tokens in light mode', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(PitPalette.canvasOf(context), PitPalette.lightCanvas);
      expect(PitPalette.surfaceOf(context), PitPalette.lightSurface);
      expect(
        PitPalette.surfaceStrongOf(context),
        PitPalette.lightSurfaceStrong,
      );
      expect(PitPalette.outlineOf(context), PitPalette.lightOutline);
      expect(PitPalette.inkOf(context), PitPalette.lightInk);
      expect(PitPalette.accentOf(context), PitPalette.violetDeep);
    });

    testWidgets('dark theme wires the Shadow Board tokens', (tester) async {
      final theme = buildDarkAppTheme();
      expect(theme.colorScheme.primary, PitPalette.violetCore);
      expect(theme.scaffoldBackgroundColor, PitPalette.caseBlack);
      expect(theme.colorScheme.outline, PitPalette.outline);
      // No shadows anywhere: depth is drawn, not floated.
      expect(theme.cardTheme.elevation, 0);
    });
  });

  // Guards for the drawn-depth and one-violet rules that a token swap could
  // silently regress (each of these caught a real gap in review).
  group('Shadow Board token guards', () {
    testWidgets(
      'sheets and dialogs draw Surface Strong plus the outline border',
      (tester) async {
        final dark = buildDarkAppTheme();
        expect(
          dark.bottomSheetTheme.backgroundColor,
          PitPalette.caseSurfaceStrong,
        );
        expect(dark.dialogTheme.backgroundColor, PitPalette.caseSurfaceStrong);
        final sheetShape =
            dark.bottomSheetTheme.shape as RoundedRectangleBorder;
        expect(sheetShape.side.color, PitPalette.outline);
        expect(dark.bottomSheetTheme.elevation, 0);

        final light = buildAppTheme();
        expect(
          light.bottomSheetTheme.backgroundColor,
          PitPalette.lightSurfaceStrong,
        );
        final lightSheetShape =
            light.bottomSheetTheme.shape as RoundedRectangleBorder;
        expect(lightSheetShape.side.color, PitPalette.lightOutline);
      },
    );

    testWidgets('secondary buttons carry Ink labels, not the violet accent', (
      tester,
    ) async {
      final theme = buildDarkAppTheme();
      final outlined = theme.outlinedButtonTheme.style!.foregroundColor!
          .resolve(<WidgetState>{});
      final text = theme.textButtonTheme.style!.foregroundColor!.resolve(
        <WidgetState>{},
      );
      expect(outlined, PitPalette.ink);
      expect(text, PitPalette.ink);
      expect(outlined, isNot(PitPalette.violetCore));
    });

    testWidgets('buttons are at least 48 tall', (tester) async {
      final theme = buildDarkAppTheme();
      final size = theme.filledButtonTheme.style!.minimumSize!.resolve(
        <WidgetState>{},
      );
      expect(size!.height, 48);
    });

    testWidgets('type scale is capped at the 18px ceiling', (tester) async {
      final t = buildDarkAppTheme().textTheme;
      for (final style in <TextStyle?>[
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
      ]) {
        expect(style!.fontSize, lessThanOrEqualTo(18));
      }
    });

    testWidgets('input focus is a 2px violet border', (tester) async {
      final theme = buildDarkAppTheme();
      final focused =
          theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
      expect(focused.borderSide.width, 2);
      expect(focused.borderSide.color, PitPalette.violetCore);
    });

    testWidgets('no Material surface tint leaks through the color scheme', (
      tester,
    ) async {
      expect(buildDarkAppTheme().colorScheme.surfaceTint, Colors.transparent);
      expect(buildAppTheme().colorScheme.surfaceTint, Colors.transparent);
    });
  });
}
