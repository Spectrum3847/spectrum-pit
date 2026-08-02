import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';

import 'support/fake_pit_shift_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

PitShift _shift(
  String id, {
  String label = 'Shift',
  ShiftKind kind = ShiftKind.pitDuty,
  String competition = 'Houston',
  List<String> assignedUids = const ['uid-1'],
  int? startMatch,
  int? endMatch,
  DateTime? startsAt,
  DateTime? endsAt,
}) => PitShift(
  id: id,
  label: label,
  kind: kind,
  competition: competition,
  assignedUids: assignedUids,
  assignedNames: const ['Tester'],
  startMatch: startMatch,
  endMatch: endMatch,
  startsAt: startsAt,
  endsAt: endsAt,
  updatedAt: DateTime.utc(2026, 1, 1),
);

DateTime _at(int hour) => DateTime.utc(2026, 4, 10, hour);

Map<String, dynamic> _cacheMap(PitShift shift) => {
  ...shift.toJson(),
  'id': shift.id,
};

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cold start loads the cache when signed out', () async {
    SharedPreferences.setMockInitialValues({
      'pit_shifts_cache': jsonEncode([
        _cacheMap(_shift('a', label: 'Cached shift', startMatch: 1)),
      ]),
    });
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(),
      syncService: FakePitShiftSyncService(),
    );

    await controller.bootstrap();

    expect(controller.items.single.label, 'Cached shift');
    expect(controller.items.single.startMatch, 1);
    controller.dispose();
  });

  test('signed-in stream emission replaces items', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([_shift('x'), _shift('y')]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((s) => s.id), ['x', 'y']);
    controller.dispose();
  });

  test('upsert adds optimistically and persists', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.upsert(_shift('a'));

    expect(controller.items.single.id, 'a');
    expect(sync.upserts.single.id, 'a');
    controller.dispose();
  });

  test('delete removes optimistically', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();
    await controller.upsert(_shift('a'));
    await controller.upsert(_shift('b'));

    await controller.delete('a');

    expect(controller.items.map((s) => s.id), ['b']);
    expect(sync.deletes.single, 'a');
    controller.dispose();
  });

  test('shiftsForCompetition filters and orders the schedule', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([
      _shift('no-range', label: 'Floating'),
      _shift('timed-late', startsAt: _at(16), endsAt: _at(18)),
      _shift('match-late', startMatch: 40, endMatch: 50),
      _shift('timed-early', startsAt: _at(8), endsAt: _at(10)),
      _shift('match-early', startMatch: 1, endMatch: 20),
      _shift('other-event', competition: 'Worlds', startMatch: 1),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.shiftsForCompetition('Houston').map((s) => s.id), [
      'match-early',
      'match-late',
      'timed-early',
      'timed-late',
      'no-range',
    ]);
    expect(controller.shiftsForCompetition('Worlds').map((s) => s.id), [
      'other-event',
    ]);
    controller.dispose();
  });

  test('shiftsForUid returns only the shifts for that uid', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([
      _shift('mine-late', startMatch: 40),
      _shift('mine-early', startMatch: 1, endMatch: 10),
      _shift('shared', assignedUids: const ['uid-2', 'uid-1'], startMatch: 20),
      _shift('theirs', assignedUids: const ['uid-2'], startMatch: 5),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.shiftsForUid('uid-1').map((s) => s.id), [
      'mine-early',
      'shared',
      'mine-late',
    ]);
    controller.dispose();
  });

  test('conflicts reports overlapping shifts for a shared assignee', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([
      _shift('duty', startsAt: _at(8), endsAt: _at(12)),
      _shift(
        'away',
        kind: ShiftKind.unavailable,
        startsAt: _at(10),
        endsAt: _at(14),
      ),
      _shift('clear', startsAt: _at(14), endsAt: _at(16)),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.conflicts.length, 1);
    expect(controller.conflicts.single.first.id, 'duty');
    expect(controller.conflicts.single.second.id, 'away');
    controller.dispose();
  });

  test(
    'stale-stream guard: emit after sign-out does not change items',
    () async {
      final auth = FakeSpectrumAuthService(initialUser: _signedInUser);
      final sync = FakePitShiftSyncService();
      final controller = PitShiftController(
        authService: auth,
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit([_shift('x')]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.items.map((s) => s.id), ['x']);

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      sync.emit([_shift('y')]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.items.map((s) => s.id), ['x']);
      controller.dispose();
    },
  );

  test('bootstrap is idempotent', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await Future.wait([controller.bootstrap(), controller.bootstrap()]);

    sync.emit([_shift('x')]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((s) => s.id), ['x']);
    controller.dispose();
  });

  test('a stream error keeps the last items and does not crash', () async {
    final sync = FakePitShiftSyncService();
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([_shift('x')]);
    await Future<void>.delayed(Duration.zero);

    // Capture debugPrint so the test proves onError actually ran, rather than
    // passing just because an unhandled stream error goes unnoticed here.
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);

    sync.emitError(Exception('permission-denied'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((s) => s.id), ['x']);
    expect(
      logged.where((m) => m.contains('PitShiftController sync stream error')),
      isNotEmpty,
    );
    controller.dispose();
  });

  test('disposing while bootstrap is in flight does not throw', () async {
    final controller = PitShiftController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: FakePitShiftSyncService(),
    );

    // Do not await: dispose lands while bootstrap is still reading the cache.
    final booting = controller.bootstrap();
    controller.dispose();

    await expectLater(booting, completes);
  });
}
