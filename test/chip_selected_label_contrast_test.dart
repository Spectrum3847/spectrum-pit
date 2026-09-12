import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/theme/pit_palette.dart';

double _relativeLuminance(Color c) {
  double linear(double channel) => channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  final r = linear(c.r);
  final g = linear(c.g);
  final b = linear(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

Color? _paintedLabelColor(WidgetTester tester, String label) {
  return tester
      .renderObject<RenderParagraph>(find.text(label))
      .text
      .style
      ?.color;
}

Future<void> _pumpChips(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Wrap(
          children: [
            FilterChip(
              label: const Text('unselected'),
              selected: false,
              onSelected: (_) {},
            ),
            FilterChip(
              label: const Text('selected'),
              selected: true,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('selected chip label contrast', () {
    testWidgets(
      'dark theme: selected label clears WCAG AA against the accent fill',
      (tester) async {
        await _pumpChips(tester, buildDarkAppTheme());

        final unselected = _paintedLabelColor(tester, 'unselected');
        final selected = _paintedLabelColor(tester, 'selected');

        expect(unselected, PitPalette.ink);
        expect(selected, isNotNull);
        final ratio = _contrastRatio(selected!, PitPalette.violetCore);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'selected label vs violetCore fill measured $ratio:1',
        );
      },
    );

    testWidgets(
      'light theme: selected label clears WCAG AA against the accent fill',
      (tester) async {
        await _pumpChips(tester, buildAppTheme());

        final unselected = _paintedLabelColor(tester, 'unselected');
        final selected = _paintedLabelColor(tester, 'selected');

        expect(unselected, PitPalette.lightInk);
        expect(selected, isNotNull);
        final ratio = _contrastRatio(selected!, PitPalette.violetDeep);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'selected label vs violetDeep fill measured $ratio:1',
        );
      },
    );
  });
}
