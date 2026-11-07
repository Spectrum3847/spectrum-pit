import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/tour_service.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/welcome_tour.dart';

Future<({List<TourStep> seen, List<String> done})> _pumpOverlay(
  WidgetTester tester, {
  required List<int> tabs,
  bool withBottomBar = false,
}) async {
  final seen = <TourStep>[];
  final done = <String>[];
  final navKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkAppTheme(),
      home: Stack(
        children: [
          Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: withBottomBar
                ? NavigationBar(
                    key: navKey,
                    destinations: const [
                      NavigationDestination(icon: Icon(Icons.home), label: 'A'),
                      NavigationDestination(icon: Icon(Icons.map), label: 'B'),
                    ],
                  )
                : null,
          ),
          WelcomeTourOverlay(
            steps: buildTourSteps(tabs),
            navKey: withBottomBar ? navKey : null,
            onDone: () => done.add('done'),
            onStepChanged: seen.add,
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (seen: seen, done: done);
}

void main() {
  test('steps follow the given tabs and skip unknown ones', () {
    final steps = buildTourSteps(const [
      AppTabs.packing,
      AppTabs.inventory,
      99,
      AppTabs.settings,
    ]);
    expect(steps.map((s) => s.title), [
      'Welcome to Spectrum Pit',
      'Packing',
      'Inventory',
      'Settings',
    ]);
    expect(steps.first.tabIndex, isNull);
    expect(steps[1].tabIndex, AppTabs.packing);
  });

  test('every tab has a step', () {
    const all = [
      AppTabs.now,
      AppTabs.inventory,
      AppTabs.packing,
      AppTabs.borrowed,
      AppTabs.maps,
      AppTabs.schedule,
      AppTabs.docs,
      AppTabs.users,
      AppTabs.settings,
      AppTabs.usage,
      AppTabs.robotLogs,
    ];
    expect(buildTourSteps(all), hasLength(all.length + 1));
  });

  testWidgets('Next and Back walk the steps and report each one', (
    tester,
  ) async {
    final r = await _pumpOverlay(
      tester,
      tabs: const [AppTabs.inventory, AppTabs.maps],
    );
    expect(find.text('Welcome to Spectrum Pit'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(r.seen.single.tabIndex, isNull);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory'), findsOneWidget);
    expect(r.seen.last.tabIndex, AppTabs.inventory);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Maps'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory'), findsOneWidget);
    expect(r.seen.last.tabIndex, AppTabs.inventory);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    expect(r.done, ['done']);
  });

  testWidgets('Skip finishes the tour', (tester) async {
    final r = await _pumpOverlay(tester, tabs: const [AppTabs.inventory]);
    await tester.tap(find.text('Skip'));
    expect(r.done, ['done']);
  });

  testWidgets('the card sits above a bottom navigation bar', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpOverlay(
      tester,
      tabs: const [AppTabs.inventory],
      withBottomBar: true,
    );
    final bar = tester.getRect(find.byType(NavigationBar));
    final next = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
    expect(next.bottom, lessThanOrEqualTo(bar.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card fits 200% text on a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpOverlay(tester, tabs: const [AppTabs.packing]);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Packing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('SharedPreferencesTourService persists the seen flag', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = SharedPreferencesTourService();
    expect(await service.isSeen(), isFalse);
    await service.markSeen();
    expect(await SharedPreferencesTourService().isSeen(), isTrue);
  });
}
