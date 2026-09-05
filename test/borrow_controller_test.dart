import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';

import 'support/fake_borrow_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

BorrowRecord _item(
  String id, {
  String toolName = 'Drill',
  DateTime? estimatedReturn,
  bool returned = false,
}) => BorrowRecord(
  id: id,
  toolName: toolName,
  teamName: 'Robowizards',
  teamNumber: 1234,
  competition: 'Regional',
  checkedOutAt: DateTime.utc(2026, 1, 1),
  estimatedReturn: estimatedReturn,
  returned: returned,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Map<String, dynamic> _cacheMap(BorrowRecord item) => {
  ...item.toJson(),
  'id': item.id,
};

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBorrowSyncService sync;

  setUp(() {
    sync = FakeBorrowSyncService();
    SharedPreferences.setMockInitialValues({});
  });

  test('cold start loads the cache when signed out', () async {
    final cached = _item('a', toolName: 'Cached Tool');
    SharedPreferences.setMockInitialValues({
      'pit_borrow_cache': jsonEncode([_cacheMap(cached)]),
    });
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );

    await controller.bootstrap();

    expect(controller.items.length, 1);
    expect(controller.items.single.id, 'a');
    expect(controller.items.single.toolName, 'Cached Tool');
    controller.dispose();
  });

  test('signed-in stream emission replaces items and notifies', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    var notified = false;
    controller.addListener(() => notified = true);

    sync.emit([_item('x'), _item('y')]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((i) => i.id), ['x', 'y']);
    expect(notified, isTrue);
    controller.dispose();
  });

  test('upsert adds optimistically, records the call, and persists', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.upsert(_item('a'));

    expect(controller.items.single.id, 'a');
    expect(sync.upserts.single.id, 'a');

    final reopened = BorrowController(
      authService: FakeSpectrumAuthService(),
      syncService: FakeBorrowSyncService(),
    );
    await reopened.bootstrap();
    expect(reopened.items.single.id, 'a');
    controller.dispose();
    reopened.dispose();
  });

  test('overdueCount is zero with no overdue loans', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();

    expect(controller.overdueCount, 0);

    final now = DateTime.now();
    await controller.upsert(
      _item('a', estimatedReturn: now.add(const Duration(hours: 1))),
    );
    await controller.upsert(_item('b'));

    expect(controller.overdueCount, 0);
    controller.dispose();
  });

  test(
    'overdueCount counts active loans past their estimated return',
    () async {
      final controller = BorrowController(
        authService: FakeSpectrumAuthService(),
        syncService: sync,
      );
      await controller.bootstrap();
      final now = DateTime.now();
      await controller.upsert(
        _item('a', estimatedReturn: now.subtract(const Duration(hours: 1))),
      );
      await controller.upsert(
        _item('b', estimatedReturn: now.subtract(const Duration(minutes: 5))),
      );
      await controller.upsert(
        _item('c', estimatedReturn: now.add(const Duration(hours: 1))),
      );

      expect(controller.overdueCount, 2);
      controller.dispose();
    },
  );

  test(
    'overdueCount excludes a returned loan past its estimated return',
    () async {
      final controller = BorrowController(
        authService: FakeSpectrumAuthService(),
        syncService: sync,
      );
      await controller.bootstrap();
      final now = DateTime.now();
      await controller.upsert(
        _item(
          'a',
          estimatedReturn: now.subtract(const Duration(hours: 1)),
          returned: true,
        ),
      );

      expect(controller.overdueCount, 0);
      controller.dispose();
    },
  );

  test('delete removes optimistically and records the call', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();
    await controller.upsert(_item('a'));
    await controller.upsert(_item('b'));

    await controller.delete('a');

    expect(controller.items.map((i) => i.id), ['b']);
    expect(sync.deletes.single, 'a');
    controller.dispose();
  });

  test(
    'stale-stream guard: emit after sign-out does not change items',
    () async {
      final auth = FakeSpectrumAuthService(initialUser: _signedInUser);
      final controller = BorrowController(authService: auth, syncService: sync);
      await controller.bootstrap();

      sync.emit([_item('x')]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.items.map((i) => i.id), ['x']);

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      sync.emit([_item('y'), _item('z')]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.items.map((i) => i.id), ['x']);
      controller.dispose();
    },
  );

  test('bootstrap is idempotent', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await Future.wait([controller.bootstrap(), controller.bootstrap()]);

    sync.emit([_item('x')]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((i) => i.id), ['x']);
    controller.dispose();
  });

  test('dispose does not throw and stops updates', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    controller.dispose();

    sync.emit([_item('x')]);
    await Future<void>.delayed(Duration.zero);
  });

  test('a stream error keeps the last items and does not crash', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([_item('x')]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.items.map((i) => i.id), ['x']);

    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);

    sync.emitError(Exception('permission-denied'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((i) => i.id), ['x']);
    expect(
      logged.where((m) => m.contains('BorrowController sync stream error')),
      isNotEmpty,
    );
    controller.dispose();
  });

  test('disposing while bootstrap is in flight does not throw', () async {
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );

    final booting = controller.bootstrap();
    controller.dispose();

    await expectLater(booting, completes);
  });
}
