import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/driver_schedule.dart';
import 'package:spectrumpit/src/services/driver_schedule_generator.dart';
import 'package:spectrumpit/src/services/driver_schedule_store.dart';
import 'package:spectrumpit/src/services/event_match_schedule.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/driver_schedule_screen.dart';

void main() {
  const matches = EventMatchSchedule(
    eventKey: '2026txhou',
    teams: [3847, 118],
    matchNumbers: [4, 9, 12],
    plays: [
      [0, 2],
      [1, 2],
    ],
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    EventMatchLoader? loader,
    String? competition,
    DriverScheduleStore? store,
  }) async {
    tester.view.physicalSize = const Size(1100, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: DriverScheduleScreen(
          generator: DriverScheduleGenerator(random: Random(5)),
          eventMatchLoader: loader,
          competition: competition,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> twoRobots(WidgetTester tester) async {
    await tester.tap(find.text('Two robots'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Driver').first,
      'Ada\nBen',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Driver').at(1),
      'Cy\nDee',
    );
  }

  Future<void> setEvent(WidgetTester tester, {List<String>? teams}) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Event key (optional)'),
      '2026TXHOU ',
    );
    final fields = find.widgetWithText(TextField, 'Team number');
    final values = teams ?? ['3847', '118'];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
    await tester.pump();
  }

  Future<void> generate(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();
  }

  testWidgets('one robot and no loader offer no event key', (tester) async {
    await pumpScreen(tester, loader: (_, _) async => matches);
    expect(
      find.widgetWithText(TextField, 'Event key (optional)'),
      findsNothing,
    );

    await pumpScreen(tester);
    await tester.tap(find.text('Two robots'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'Event key (optional)'),
      findsNothing,
    );
  });

  testWidgets('an event key builds the rotation on the real matches', (
    tester,
  ) async {
    String? askedEvent;
    List<int>? askedTeams;
    await pumpScreen(
      tester,
      loader: (event, teams) async {
        askedEvent = event;
        askedTeams = teams;
        return matches;
      },
    );
    await twoRobots(tester);
    await setEvent(tester);

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Matches'))
          .enabled,
      isFalse,
    );

    await generate(tester);

    expect(askedEvent, '2026txhou');
    expect(askedTeams, [3847, 118]);
    expect(find.text('Robot 1, team 3847'), findsOneWidget);
    expect(find.text('Robot 2, team 118'), findsOneWidget);

    expect(find.text('Q4'), findsOneWidget);
    expect(find.text('Q9'), findsOneWidget);
    expect(find.text('Q12'), findsNWidgets(2));
    expect(
      find.textContaining('Robots in the same match: Q12 (robots 1 and 2)'),
      findsOneWidget,
    );
  });

  testWidgets('a missing team number is asked for, not loaded', (tester) async {
    var calls = 0;
    await pumpScreen(
      tester,
      loader: (_, _) async {
        calls++;
        return matches;
      },
    );
    await twoRobots(tester);
    await setEvent(tester, teams: ['3847']);
    await generate(tester);

    expect(calls, 0);
    expect(find.text('Enter a team number for every robot.'), findsOneWidget);
    expect(find.text('Matches per person'), findsNothing);
  });

  testWidgets('a load failure explains itself', (tester) async {
    await pumpScreen(
      tester,
      loader: (_, _) async =>
          throw const EventScheduleException('No qualification matches.'),
    );
    await twoRobots(tester);
    await setEvent(tester);
    await generate(tester);

    expect(find.text('No qualification matches.'), findsOneWidget);
    expect(find.text('Matches per person'), findsNothing);
  });

  testWidgets('shows that it is loading', (tester) async {
    final pending = Completer<EventMatchSchedule>();
    await pumpScreen(tester, loader: (_, _) => pending.future);
    await twoRobots(tester);
    await setEvent(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pump();

    expect(find.text('Loading matches'), findsOneWidget);
    pending.complete(matches);
    await tester.pumpAndSettle();
    expect(find.text('Q4'), findsOneWidget);
  });

  testWidgets('asking again mid-load starts no second load', (tester) async {
    final pending = Completer<EventMatchSchedule>();
    var calls = 0;
    await pumpScreen(
      tester,
      loader: (_, _) {
        calls++;
        return pending.future;
      },
    );
    await twoRobots(tester);
    await setEvent(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pump();

    await tester.showKeyboard(
      find.widgetWithText(TextField, 'Event key (optional)'),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(calls, 1);
    pending.complete(matches);
    await tester.pumpAndSettle();
    expect(find.text('Q4'), findsOneWidget);
  });

  testWidgets('an event key changed mid-load loads the new one', (
    tester,
  ) async {
    final first = Completer<EventMatchSchedule>();
    final asked = <String>[];
    await pumpScreen(
      tester,
      loader: (event, _) {
        asked.add(event);
        return asked.length == 1 ? first.future : Future.value(matches);
      },
    );
    await twoRobots(tester);
    await setEvent(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Event key (optional)'),
      '2026casj',
    );
    first.complete(matches);
    await tester.pumpAndSettle();

    expect(asked, ['2026txhou', '2026casj']);
  });

  testWidgets('the hand-off toggle reuses the matches on screen', (
    tester,
  ) async {
    var calls = 0;
    await pumpScreen(
      tester,
      loader: (_, _) async {
        calls++;
        return matches;
      },
    );
    await twoRobots(tester);
    await setEvent(tester);
    await generate(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Q4'), findsOneWidget);
  });

  testWidgets('each chart offers its image', (tester) async {
    await pumpScreen(tester, loader: (_, _) async => matches);
    await twoRobots(tester);
    await setEvent(tester);
    await generate(tester);

    expect(find.widgetWithText(TextButton, 'Share image'), findsNWidgets(2));
  });

  testWidgets('a saved event rotation brings its event and teams back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = DriverScheduleStore();
    await store.save(
      'Houston',
      SavedDriverSchedule(
        mode: twoRobotConfig.label,
        slots: 3,
        handoff: false,
        inputs: const {
          'r1driver': ['Ada'],
          'r2driver': ['Cy'],
        },
        grid: const {
          'r1driver': ['Ada', '', 'Ada'],
          'r2driver': ['', 'Cy', 'Cy'],
        },
        updatedAt: DateTime.utc(2026, 10, 17),
        matches: matches,
      ),
    );

    await pumpScreen(
      tester,
      loader: (_, _) async => matches,
      competition: 'Houston',
      store: store,
    );

    String textOf(Finder field) =>
        tester.widget<TextField>(field).controller!.text;
    expect(
      textOf(find.widgetWithText(TextField, 'Event key (optional)')),
      '2026txhou',
    );
    final teams = find.widgetWithText(TextField, 'Team number');
    expect(textOf(teams.at(0)), '3847');
    expect(textOf(teams.at(1)), '118');
    expect(find.text('Q12'), findsNWidgets(2));
  });
}
