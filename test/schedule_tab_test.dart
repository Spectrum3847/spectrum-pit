import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/schedule_tab.dart';

import 'support/fake_pit_shift_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

const _me = SpectrumUser(
  uid: 'uid-me',
  displayName: 'Alex Reyes',
  email: 'alex@example.com',
);

PitShift _shift(
  String id, {
  required String label,
  ShiftKind kind = ShiftKind.pitDuty,
  String competition = 'Houston',
  List<String> uids = const ['uid-me'],
  List<String> names = const ['Alex Reyes'],
  int? startMatch,
  int? endMatch,
}) => PitShift(
  id: id,
  label: label,
  kind: kind,
  competition: competition,
  assignedUids: uids,
  assignedNames: names,
  startMatch: startMatch,
  endMatch: endMatch,
  updatedAt: DateTime.utc(2026, 4, 10),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePitShiftSyncService sync;
  late PitShiftController controller;

  setUp(() {
    sync = FakePitShiftSyncService();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() => controller.dispose());

  Future<void> pumpTab(
    WidgetTester tester, {
    List<PitShift> shifts = const <PitShift>[],
    SpectrumUser? user = _me,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Signed out there is no sync stream, so the offline cache is the only way
    // shifts reach the tab.
    if (user == null && shifts.isNotEmpty) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pit_shifts_cache': jsonEncode([
          for (final shift in shifts) {...shift.toJson(), 'id': shift.id},
        ]),
      });
    }

    final auth = FakeSpectrumAuthService(initialUser: user);
    final roleService = FakeUserRoleService();
    if (user != null) roleService.setRoles(user.uid, {UserRole.pit});
    final roleController = UserRoleController(
      authService: auth,
      roleService: roleService,
    );
    await roleController.bootstrap();
    controller = PitShiftController(authService: auth, syncService: sync);
    await controller.bootstrap();
    if (shifts.isNotEmpty && user != null) sync.emit(shifts);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: Scaffold(
          body: ScheduleTab(
            controller: controller,
            authService: auth,
            roleController: roleController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty schedule shows the slot and an add action', (
    tester,
  ) async {
    await pumpTab(tester);

    expect(find.text('No shifts scheduled'), findsOneWidget);
    // The FAB and the slot both offer the verb.
    expect(find.text('Add shift'), findsNWidgets(2));
  });

  testWidgets('a member sees the competition schedule with mono ranges', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [
        _shift(
          'a',
          label: 'Qual block',
          kind: ShiftKind.matchBlock,
          startMatch: 18,
          endMatch: 34,
        ),
        _shift(
          'b',
          label: 'Trailer unload',
          kind: ShiftKind.loadIn,
          startMatch: 1,
          endMatch: 4,
          uids: const ['uid-other'],
          names: const ['Sam Ito'],
        ),
      ],
    );

    expect(find.text('Qual block'), findsOneWidget);
    expect(find.text('Trailer unload'), findsOneWidget);
    expect(find.text('M18-M34'), findsOneWidget);
    expect(find.text('M1-M4'), findsOneWidget);
    // Kinds render as a label, never colour alone.
    expect(find.text('Match block'), findsOneWidget);
    expect(find.text('Load in'), findsOneWidget);
  });

  testWidgets('a double-booking names the person and both blocks', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [
        _shift('a', label: 'Pit duty', startMatch: 20, endMatch: 40),
        _shift(
          'b',
          label: 'Qual block',
          kind: ShiftKind.matchBlock,
          startMatch: 30,
          endMatch: 50,
        ),
      ],
    );

    expect(find.text('1 conflict'), findsOneWidget);
    expect(
      find.textContaining(
        'Alex Reyes: "Pit duty" M20-M40 overlaps "Qual block" M30-M50',
      ),
      findsOneWidget,
    );
    // Both rows carry the word, not just the alert hue.
    expect(find.text('Conflict'), findsNWidgets(2));
  });

  testWidgets('an assignment inside unavailable time reads as such', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [
        _shift(
          'away',
          label: 'Driving home',
          kind: ShiftKind.unavailable,
          startMatch: 55,
          endMatch: 70,
        ),
        _shift(
          'out',
          label: 'Load out',
          kind: ShiftKind.loadOut,
          startMatch: 60,
          endMatch: 80,
        ),
      ],
    );

    expect(
      find.textContaining(
        'Alex Reyes: "Load out" M60-M80 falls in unavailable time '
        '"Driving home" M55-M70',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Mine narrows the schedule to the signed-in user', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [
        _shift('a', label: 'Qual block', startMatch: 18, endMatch: 34),
        _shift(
          'b',
          label: 'Trailer unload',
          startMatch: 1,
          endMatch: 4,
          uids: const ['uid-other'],
          names: const ['Sam Ito'],
        ),
      ],
    );

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();

    expect(find.text('Qual block'), findsOneWidget);
    expect(find.text('Trailer unload'), findsNothing);
  });

  testWidgets('marking yourself unavailable writes an unavailable block', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
    );

    await tester.tap(find.text('Mark unavailable'));
    await tester.pumpAndSettle();

    // The form talks about the person, not about a kind of shift.
    expect(find.text('Mark yourself unavailable'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Reason'), findsOneWidget);
    expect(find.text('Type'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Drivers meeting',
    );
    await tester.tap(find.text('Match'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'First match'), '40');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Mark unavailable'));
    await tester.pumpAndSettle();

    final saved = sync.upserts.single;
    expect(saved.kind, ShiftKind.unavailable);
    expect(saved.label, 'Drivers meeting');
    expect(saved.competition, 'Houston');
    expect(saved.assignedUids, ['uid-me']);
    expect(saved.assignedNames, ['Alex Reyes']);
    expect(saved.startMatch, 40);
    expect(saved.startsAt, isNull);
  });

  testWidgets('the shift form offers the roster and saves both name lists', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [
        _shift(
          'a',
          label: 'Qual block',
          startMatch: 18,
          endMatch: 34,
          uids: const ['uid-other'],
          names: const ['Sam Ito'],
        ),
      ],
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Self plus everyone already on the schedule, no roster read required.
    expect(find.widgetWithText(FilterChip, 'Alex Reyes'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Sam Ito'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Shift name'),
      'Load out crew',
    );
    await tester.enterText(find.widgetWithText(TextField, 'First match'), '80');
    await tester.tap(find.widgetWithText(FilterChip, 'Sam Ito'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add shift'));
    await tester.pumpAndSettle();

    final saved = sync.upserts.single;
    expect(saved.label, 'Load out crew');
    expect(saved.assignedUids, containsAll(<String>['uid-me', 'uid-other']));
    expect(saved.assignedNames, containsAll(<String>['Alex Reyes', 'Sam Ito']));
  });

  testWidgets('signed out, the Mine view says to sign in', (tester) async {
    await pumpTab(
      tester,
      user: null,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
    );

    // No account, so no self-service availability action.
    expect(find.text('Mark unavailable'), findsNothing);

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
  });
}
