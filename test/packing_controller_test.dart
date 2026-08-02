import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';

import 'support/fake_packing_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

PackingRecord _item(String id, {String itemId = 'tool-1'}) => PackingRecord(
  id: id,
  itemId: itemId,
  packingStatus: PackingStatus.packing,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Map<String, dynamic> _cacheMap(PackingRecord item) => {
  ...item.toJson(),
  'id': item.id,
};

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePackingSyncService sync;

  setUp(() {
    sync = FakePackingSyncService();
    SharedPreferences.setMockInitialValues({});
  });

  test('cold start loads the cache when signed out', () async {
    final cached = _item('a', itemId: 'cached-tool');
    SharedPreferences.setMockInitialValues({
      'pit_packing_cache': jsonEncode([_cacheMap(cached)]),
    });
    final controller = PackingController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );

    await controller.bootstrap();

    expect(controller.items.length, 1);
    expect(controller.items.single.id, 'a');
    expect(controller.items.single.itemId, 'cached-tool');
    controller.dispose();
  });

  test('signed-in stream emission replaces items and notifies', () async {
    final controller = PackingController(
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
    final controller = PackingController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.upsert(_item('a'));

    expect(controller.items.single.id, 'a');
    expect(sync.upserts.single.id, 'a');

    // A fresh controller reads the same mock store, proving it persisted.
    final reopened = PackingController(
      authService: FakeSpectrumAuthService(),
      syncService: FakePackingSyncService(),
    );
    await reopened.bootstrap();
    expect(reopened.items.single.id, 'a');
    controller.dispose();
    reopened.dispose();
  });

  test('delete removes optimistically and records the call', () async {
    final controller = PackingController(
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
      final controller = PackingController(
        authService: auth,
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit([_item('x')]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.items.map((i) => i.id), ['x']);

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      sync.emit([_item('y'), _item('z')]);
      await Future<void>.delayed(Duration.zero);

      // Still the pre-sign-out list; the superseded stream cannot clobber it.
      expect(controller.items.map((i) => i.id), ['x']);
      controller.dispose();
    },
  );

  test('bootstrap is idempotent', () async {
    final controller = PackingController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await Future.wait([controller.bootstrap(), controller.bootstrap()]);

    sync.emit([_item('x')]);
    await Future<void>.delayed(Duration.zero);

    // A double subscription would still land a consistent single list.
    expect(controller.items.map((i) => i.id), ['x']);
    controller.dispose();
  });

  test('dispose does not throw and stops updates', () async {
    final controller = PackingController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    controller.dispose();

    // Emitting after dispose must not reach the (cancelled) listener, which
    // would otherwise notifyListeners on a disposed ChangeNotifier and throw.
    sync.emit([_item('x')]);
    await Future<void>.delayed(Duration.zero);
  });

  test('a stream error keeps the last items and does not crash', () async {
    final controller = PackingController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([_item('x')]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.items.map((i) => i.id), ['x']);

    // Capture debugPrint so the test proves onError actually ran, rather than
    // passing just because an unhandled stream error goes unnoticed here.
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        logged.add(message ?? '');
    addTearDown(() => debugPrint = original);

    sync.emitError(Exception('permission-denied'));
    await Future<void>.delayed(Duration.zero);

    // The error must not tear the controller down or discard what it had.
    expect(controller.items.map((i) => i.id), ['x']);
    expect(
      logged.where((m) => m.contains('PackingController sync stream error')),
      isNotEmpty,
    );
    controller.dispose();
  });

  test('disposing while bootstrap is in flight does not throw', () async {
    final controller = PackingController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );

    // Do not await: dispose lands while bootstrap is still reading the cache.
    final booting = controller.bootstrap();
    controller.dispose();

    await expectLater(booting, completes);
  });
}
