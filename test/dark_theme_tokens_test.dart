import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/theme/pit_palette.dart';

void main() {
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

    test('dark theme wires the Shadow Board tokens', () {
      final theme = buildDarkAppTheme();
      expect(theme.colorScheme.primary, PitPalette.violetCore);
      expect(theme.scaffoldBackgroundColor, PitPalette.caseBlack);
      expect(theme.colorScheme.outline, PitPalette.outline);

      expect(theme.cardTheme.elevation, 0);
    });
  });

  group('Shadow Board token guards', () {
    test('sheets and dialogs draw Surface Strong plus the outline border', () {
      final dark = buildDarkAppTheme();
      expect(
        dark.bottomSheetTheme.backgroundColor,
        PitPalette.caseSurfaceStrong,
      );
      expect(dark.dialogTheme.backgroundColor, PitPalette.caseSurfaceStrong);
      final sheetShape = dark.bottomSheetTheme.shape as RoundedRectangleBorder;
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
    });

    test('secondary buttons carry Ink labels, not the violet accent', () {
      for (final (theme, ink) in [
        (buildDarkAppTheme(), PitPalette.ink),
        (buildAppTheme(), PitPalette.lightInk),
      ]) {
        final outlined = theme.outlinedButtonTheme.style!.foregroundColor!
            .resolve(<WidgetState>{});
        final text = theme.textButtonTheme.style!.foregroundColor!.resolve(
          <WidgetState>{},
        );
        expect(outlined, ink);
        expect(text, ink);
        expect(outlined, isNot(PitPalette.violetCore));
      }
    });

    test('buttons are at least 48 tall', () {
      for (final theme in [buildDarkAppTheme(), buildAppTheme()]) {
        final size = theme.filledButtonTheme.style!.minimumSize!.resolve(
          <WidgetState>{},
        );
        expect(size!.height, 48);
      }
    });

    test('type scale is capped at the 18px ceiling', () {
      for (final theme in [buildDarkAppTheme(), buildAppTheme()]) {
        final t = theme.textTheme;
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
      }
    });

    test('input focus is a 2px violet border', () {
      for (final (theme, accent) in [
        (buildDarkAppTheme(), PitPalette.violetCore),
        (buildAppTheme(), PitPalette.violetDeep),
      ]) {
        final focused =
            theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
        expect(focused.borderSide.width, 2);
        expect(focused.borderSide.color, accent);
      }
    });

    test('no Material surface tint leaks through the color scheme', () {
      expect(buildDarkAppTheme().colorScheme.surfaceTint, Colors.transparent);
      expect(buildAppTheme().colorScheme.surfaceTint, Colors.transparent);
    });
  });

  group('status tokens resolve per brightness', () {
    Future<BuildContext> pump(WidgetTester tester, ThemeData theme) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return context;
    }

    testWidgets('dark mode resolves the dark status tokens', (tester) async {
      final context = await pump(tester, buildDarkAppTheme());

      expect(PitPalette.statusPackingOf(context), PitPalette.statusPacking);
      expect(PitPalette.statusStagingOf(context), PitPalette.statusStaging);
      expect(PitPalette.statusLoadingOf(context), PitPalette.statusLoading);
      expect(PitPalette.statusReadyOf(context), PitPalette.statusReady);
      expect(PitPalette.statusOverdueOf(context), PitPalette.statusOverdue);
    });

    testWidgets('light mode resolves the light status tokens', (tester) async {
      final context = await pump(tester, buildAppTheme());

      expect(
        PitPalette.statusPackingOf(context),
        PitPalette.lightStatusPacking,
      );
      expect(
        PitPalette.statusStagingOf(context),
        PitPalette.lightStatusStaging,
      );
      expect(
        PitPalette.statusLoadingOf(context),
        PitPalette.lightStatusLoading,
      );
      expect(PitPalette.statusReadyOf(context), PitPalette.lightStatusReady);
      expect(
        PitPalette.statusOverdueOf(context),
        PitPalette.lightStatusOverdue,
      );
    });

    test('no status token is shared across the two themes', () {
      const dark = <Color>[
        PitPalette.statusPacking,
        PitPalette.statusStaging,
        PitPalette.statusLoading,
        PitPalette.statusReady,
        PitPalette.statusOverdue,
      ];
      const light = <Color>[
        PitPalette.lightStatusPacking,
        PitPalette.lightStatusStaging,
        PitPalette.lightStatusLoading,
        PitPalette.lightStatusReady,
        PitPalette.lightStatusOverdue,
      ];

      for (var i = 0; i < dark.length; i++) {
        expect(dark[i], isNot(light[i]), reason: 'index $i');
      }
    });
  });
}
