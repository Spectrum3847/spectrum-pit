import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/active_event.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/models/scout_shift_mirror.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/active_event_controller.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';
import 'package:spectrumpit/src/state/scout_shift_mirror_controller.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/schedule_tab.dart';
import 'package:tba_client/tba_client.dart';

import 'support/fake_active_event_sync_service.dart';
import 'support/fake_pit_shift_sync_service.dart';
import 'support/fake_scout_shift_mirror_sync_service.dart';
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
  late FakeScoutShiftMirrorSyncService scoutSync;
  PitShiftController? controller;
  ScoutShiftMirrorController? scoutShiftController;
  ActiveEventController? activeEventController;
  late FakeActiveEventSyncService eventSync;

  setUp(() {
    eventSync = FakeActiveEventSyncService();
    activeEventController = null;
    sync = FakePitShiftSyncService();
    scoutSync = FakeScoutShiftMirrorSyncService();

    controller = null;
    scoutShiftController = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    controller?.dispose();
    scoutShiftController?.dispose();
    activeEventController?.dispose();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    List<PitShift> shifts = const <PitShift>[],
    List<ScoutShiftMirror> mirrors = const <ScoutShiftMirror>[],
    SpectrumUser? user = _me,
    List<TbaEvent>? events,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await controller!.bootstrap();
    if (shifts.isNotEmpty && user != null) sync.emit(shifts);

    scoutShiftController = ScoutShiftMirrorController(
      authService: auth,
      syncService: scoutSync,
    );
    await scoutShiftController!.bootstrap();
    if (user != null) scoutSync.emit(mirrors);

    if (events != null) {
      activeEventController = ActiveEventController(
        authService: auth,
        syncService: eventSync,
      );
      await activeEventController!.bootstrap();
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: Scaffold(
          body: ScheduleTab(
            controller: controller!,
            scoutShiftController: scoutShiftController!,
            authService: auth,
            roleController: roleController,
            activeEventController: activeEventController,
            loadEvents: events == null ? null : (_) async => events,
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

  testWidgets('the scouting rotation shows name and match ranges', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
      mirrors: [
        ScoutShiftMirror(
          eventKey: '2026miket',
          competition: 'Houston',
          matchCount: 80,
          syncedAt: DateTime.utc(2026, 4, 10, 6, 12),
          rotations: const [
            ScoutRotation(
              uid: 'uid-me',
              name: 'Alex Reyes',
              shifts: [
                MatchRange(startMatch: 1, endMatch: 6),
                MatchRange(startMatch: 13, endMatch: 18),
              ],
            ),
          ],
        ),
      ],
    );

    expect(find.text('Scouting shifts'), findsOneWidget);
    expect(find.text('Alex Reyes'), findsAtLeastNWidgets(1));
    expect(find.text('Q1-6, Q13-18'), findsOneWidget);
  });

  testWidgets('Mine hides other people from the scouting rotation', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
      mirrors: [
        ScoutShiftMirror(
          eventKey: '2026miket',
          competition: 'Houston',
          matchCount: 80,
          syncedAt: DateTime.utc(2026, 4, 10, 6, 12),
          rotations: const [
            ScoutRotation(
              uid: 'uid-me',
              name: 'Alex Reyes',
              shifts: [MatchRange(startMatch: 1, endMatch: 6)],
            ),
            ScoutRotation(
              uid: 'uid-other',
              name: 'Sam Ito',
              shifts: [MatchRange(startMatch: 7, endMatch: 12)],
            ),
          ],
        ),
      ],
    );

    expect(find.text('Alex Reyes'), findsAtLeastNWidgets(1));
    expect(find.text('Sam Ito'), findsOneWidget);

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();

    expect(find.text('Alex Reyes'), findsAtLeastNWidgets(1));
    expect(find.text('Sam Ito'), findsNothing);
  });

  testWidgets('signed out, the Mine view says to sign in', (tester) async {
    await pumpTab(
      tester,
      user: null,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
    );

    expect(find.text('Mark unavailable'), findsNothing);

    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
  });

  testWidgets('cancelling a delete keeps the shift and records no delete', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
    );

    await tester.tap(find.text('Qual block'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(sync.deletes, isEmpty);
    expect(controller!.items.single.id, 'a');
  });

  testWidgets('a confirmed delete records the shift id and closes the editor', (
    tester,
  ) async {
    await pumpTab(
      tester,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
    );

    await tester.tap(find.text('Qual block'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(sync.deletes, ['a']);
    expect(controller!.items, isEmpty);
    expect(find.text('Edit shift'), findsNothing);
  });

  testWidgets('a failed delete keeps the editor sheet open', (tester) async {
    await pumpTab(
      tester,
      shifts: [_shift('a', label: 'Qual block', startMatch: 18, endMatch: 34)],
    );
    sync.failWith = Exception('offline');

    await tester.tap(find.text('Qual block'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Edit shift'), findsOneWidget);
    expect(controller!.items.single.id, 'a');
  });

  group('team event', () {
    final now = DateTime.now();
    String day(int offset) => DateTime(
      now.year,
      now.month,
      now.day + offset,
    ).toIso8601String().substring(0, 10);
    final nearby = TbaEvent(
      key: '${now.year}txcl2',
      name: 'Lone Star Central',
      year: now.year,
      startDate: day(-1),
      endDate: day(1),
    );
    final later = TbaEvent(
      key: '${now.year}txhou',
      name: 'Houston Championship',
      year: now.year,
      startDate: day(30),
      endDate: day(33),
    );

    testWidgets('no event shows a slot that names the verb', (tester) async {
      await pumpTab(tester, events: [nearby]);

      expect(find.text('Set the team event'), findsOneWidget);
      expect(find.text('Every device follows it.'), findsOneWidget);
    });

    testWidgets('the picker lists nearby events until Show all is on', (
      tester,
    ) async {
      await pumpTab(tester, events: [nearby, later]);

      await tester.tap(find.text('Set the team event'));
      await tester.pumpAndSettle();
      expect(find.text('Lone Star Central'), findsOneWidget);
      expect(find.text('Houston Championship'), findsNothing);

      await tester.tap(find.text('Show all events'));
      await tester.pumpAndSettle();
      expect(find.text('Houston Championship'), findsOneWidget);

      await tester.tap(find.text('Houston Championship'));
      await tester.pumpAndSettle();
      expect(eventSync.writes.single.eventKey, later.key);
      expect(find.text('Houston Championship'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('the team event picks its scouting competition', (
      tester,
    ) async {
      await pumpTab(
        tester,
        events: [nearby],
        shifts: [
          _shift('a', label: 'Austin duty', competition: 'Austin'),
          _shift('h', label: 'Houston duty', competition: 'Houston'),
        ],
        mirrors: [
          ScoutShiftMirror(
            eventKey: '2026txhou',
            competition: 'Houston',
            matchCount: 80,
            syncedAt: DateTime.utc(2026, 4, 10),
            rotations: const [],
          ),
        ],
      );
      expect(find.text('Austin duty'), findsOneWidget);

      eventSync.emit(
        ActiveEvent(
          eventKey: '2026txhou',
          eventName: 'Houston',
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Houston duty'), findsOneWidget);
      expect(find.text('Austin duty'), findsNothing);
    });
  });
}
