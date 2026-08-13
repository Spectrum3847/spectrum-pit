import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/driver_schedule_generator.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/driver_schedule_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: DriverScheduleScreen(
          generator: DriverScheduleGenerator(random: Random(11)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterNames(
    WidgetTester tester,
    Map<String, String> byLabel,
  ) async {
    for (final entry in byLabel.entries) {
      await tester.enterText(
        find.widgetWithText(TextField, entry.key),
        entry.value,
      );
    }
    await tester.pump();
  }

  Future<void> generate(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();
  }

  Finder chart() => find.byType(Table).first;

  testWidgets('offers a name field per role and a generate action', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Driver schedule'), findsOneWidget);
    for (final role in ['Driver', 'Operator', 'Technician', 'Human player']) {
      expect(find.widgetWithText(TextField, role), findsOneWidget);
    }
    expect(find.widgetWithText(FilledButton, 'Generate'), findsOneWidget);
  });

  testWidgets('two-robot mode asks for the six lists under their headings', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Two robots'));
    await tester.pumpAndSettle();

    expect(find.text('Robot 1'), findsOneWidget);
    expect(find.text('Robot 2'), findsOneWidget);
    expect(find.text('Shared by both robots'), findsOneWidget);

    expect(find.widgetWithText(TextField, 'Driver'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Operator'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Technician'), findsOneWidget);
  });

  testWidgets('generating draws the chart and the attendance table', (
    tester,
  ) async {
    await pumpScreen(tester);
    await enterNames(tester, {
      'Driver': 'Alice\nBob\nCara',
      'Operator': 'Dan\nEve\nFay',
    });
    await generate(tester);

    expect(find.text('Matches per person'), findsOneWidget);
    expect(
      find.descendant(of: chart(), matching: find.text('Alice')),
      findsWidgets,
    );

    expect(
      find.descendant(of: chart(), matching: find.text('6')),
      findsOneWidget,
    );
  });

  testWidgets('chart name columns are wide enough to read', (tester) async {
    await pumpScreen(tester);
    await enterNames(tester, {'Driver': 'Alice\nBob\nCara'});
    await generate(tester);

    final cell = find
        .ancestor(
          of: find.descendant(of: chart(), matching: find.text('Alice')).first,
          matching: find.byType(Container),
        )
        .first;
    expect(tester.getSize(cell).width, greaterThanOrEqualTo(116.0));
  });

  testWidgets('an unreadable match count explains itself and draws nothing', (
    tester,
  ) async {
    await pumpScreen(tester);
    await enterNames(tester, {'Driver': 'Alice\nBob'});
    await tester.enterText(find.widgetWithText(TextField, 'Matches'), 'lots');
    await generate(tester);

    expect(find.text('Enter how many matches to schedule'), findsOneWidget);
    expect(find.text('Matches per person'), findsNothing);
  });

  testWidgets('generating with no names asks for names instead of a table', (
    tester,
  ) async {
    await pumpScreen(tester);
    await generate(tester);

    expect(
      find.text('Add at least one person to a role above, then generate.'),
      findsOneWidget,
    );
    expect(find.text('Matches per person'), findsNothing);
  });

  testWidgets('turning on the hand-off redraws the schedule on screen', (
    tester,
  ) async {
    await pumpScreen(tester);
    await enterNames(tester, {
      'Driver': 'Alice\nBob\nCara',
      'Operator': 'Alice\nBob\nCara',
    });
    await generate(tester);
    expect(find.text('Matches per person'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    expect(find.text('Matches per person'), findsOneWidget);
    expect(find.text('Operates, then drives next match'), findsOneWidget);
  });

  testWidgets('someone with no slots reads as zero, never as null', (
    tester,
  ) async {
    await pumpScreen(tester);
    await enterNames(tester, {'Driver': 'Alice\nBob\nCara\nDan'});
    await tester.enterText(find.widgetWithText(TextField, 'Matches'), '2');
    await generate(tester);

    expect(find.text('null'), findsNothing);
    expect(find.text('not listed'), findsWidgets);
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('tapping a person marks their matches in the chart', (
    tester,
  ) async {
    await pumpScreen(tester);
    await enterNames(tester, {'Driver': 'Alice\nBob'});
    await generate(tester);

    bool bordered(Widget widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).border != null;

    final before = tester.widgetList(find.byWidgetPredicate(bordered)).length;

    await tester.tap(
      find
          .descendant(of: find.byType(Table).last, matching: find.text('Alice'))
          .first,
    );
    await tester.pumpAndSettle();

    final after = tester.widgetList(find.byWidgetPredicate(bordered)).length;
    expect(after, greaterThan(before));

    await tester.tap(
      find
          .descendant(of: find.byType(Table).last, matching: find.text('Alice'))
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.widgetList(find.byWidgetPredicate(bordered)).length, before);
  });

  testWidgets('copy puts the chart on the clipboard as pasteable rows', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpScreen(tester);
    await enterNames(tester, {'Driver': 'Alice\nBob'});
    await generate(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Copy'));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied!.split('\n').first, startsWith('#\tDriver'));
    expect(copied!.split('\n').length, 7);
    expect(find.text('Schedule copied'), findsOneWidget);
  });
}
