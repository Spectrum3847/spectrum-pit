import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';

import 'support/fake_inventory_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

InventoryItem _item(String id, {String name = 'Drill'}) => InventoryItem(
  id: id,
  name: name,
  labLocation: 'Shelf A',
  pitLocation: 'Bin 1',
  status: InventoryStatus.inLab,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Map<String, dynamic> _cacheMap(InventoryItem item) => {
  ...item.toJson(),
  'id': item.id,
};

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeInventorySyncService sync;

  setUp(() {
    sync = FakeInventorySyncService();
    SharedPreferences.setMockInitialValues({});
  });

  test('cold start loads the cache when signed out', () async {
    final cached = _item('a', name: 'Cached Tool');
    SharedPreferences.setMockInitialValues({
      'pit_inventory_cache': jsonEncode([_cacheMap(cached)]),
    });
    final controller = InventoryController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );

    await controller.bootstrap();

    expect(controller.items.length, 1);
    expect(controller.items.single.id, 'a');
    expect(controller.items.single.name, 'Cached Tool');
    controller.dispose();
  });

  test('signed-in stream emission replaces items and notifies', () async {
    final controller = InventoryController(
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
    final controller = InventoryController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.upsert(_item('a'));

    expect(controller.items.single.id, 'a');
    expect(sync.upserts.single.id, 'a');

    final reopened = InventoryController(
      authService: FakeSpectrumAuthService(),
      syncService: FakeInventorySyncService(),
    );
    await reopened.bootstrap();
    expect(reopened.items.single.id, 'a');
    controller.dispose();
    reopened.dispose();
  });

  test('delete removes optimistically and records the call', () async {
    final controller = InventoryController(
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
      final controller = InventoryController(
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

      expect(controller.items.map((i) => i.id), ['x']);
      controller.dispose();
    },
  );

  test('bootstrap is idempotent', () async {
    final controller = InventoryController(
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
    final controller = InventoryController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    controller.dispose();

    sync.emit([_item('x')]);
    await Future<void>.delayed(Duration.zero);
  });

  test('a stream error keeps the last items and does not crash', () async {
    final controller = InventoryController(
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
      logged.where((m) => m.contains('InventoryController sync stream error')),
      isNotEmpty,
    );
    controller.dispose();
  });

  test('disposing while bootstrap is in flight does not throw', () async {
    final controller = InventoryController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );

    final booting = controller.bootstrap();
    controller.dispose();

    await expectLater(booting, completes);
  });

  test(
    'a delete reaches the server after an upsert already in flight',
    () async {
      final controller = InventoryController(
        authService: FakeSpectrumAuthService(initialUser: _signedInUser),
        syncService: sync,
      );
      addTearDown(controller.dispose);
      await controller.bootstrap();

      sync.holdUpsert = Completer<void>();
      final writing = controller.upsert(_item('a', name: 'Drill'));

      final deleting = controller.delete('a');
      sync.holdUpsert!.complete();
      await writing;
      await deleting;

      expect(sync.serverOps, <String>['upsert:a', 'delete:a']);
      expect(sync.storedIds, isEmpty, reason: 'the deleted item came back');
    },
  );

  test('writes to different ids do not wait on each other', () async {
    final controller = InventoryController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();

    sync.holdUpsert = Completer<void>();
    final blocked = controller.upsert(_item('a'));

    await controller.delete('b');
    expect(sync.serverOps, <String>['delete:b']);

    sync.holdUpsert!.complete();
    await blocked;
    expect(sync.serverOps, <String>['delete:b', 'upsert:a']);
  });

  test('a second consecutive failed write rolls back to the last confirmed '
      'value, not the prior failed one', () async {
    final controller = InventoryController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();

    await controller.upsert(_item('a', name: 'A'));
    expect(controller.items.single.name, 'A');

    sync.failSchedule.addAll(['b failed', 'c failed']);
    final writingB = controller
        .upsert(_item('a', name: 'B'))
        .catchError((_) {});
    final writingC = controller
        .upsert(_item('a', name: 'C'))
        .catchError((_) {});
    await writingB;
    await writingC;

    expect(controller.items.single.name, 'A');
  });
}
