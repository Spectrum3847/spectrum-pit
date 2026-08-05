import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/map_location_controller.dart';

import 'support/fake_map_location_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

MapLocation _loc(
  String id, {
  String name = 'Pin',
  MapType mapType = MapType.lab,
}) => MapLocation(
  id: id,
  name: name,
  mapType: mapType,
  x: 0.5,
  y: 0.5,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Map<String, dynamic> _cacheMap(MapLocation loc) => {
  ...loc.toJson(),
  'id': loc.id,
};

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cold start loads the cache when signed out', () async {
    final cached = _loc('a', name: 'Cached Pin');
    SharedPreferences.setMockInitialValues({
      'pit_map_locations_cache': jsonEncode([_cacheMap(cached)]),
    });
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(),
      syncService: FakeMapLocationSyncService(),
    );

    await controller.bootstrap();

    expect(controller.items.length, 1);
    expect(controller.items.single.name, 'Cached Pin');
    controller.dispose();
  });

  test('signed-in stream emission replaces items', () async {
    final sync = FakeMapLocationSyncService();
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([_loc('x'), _loc('y')]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((i) => i.id), ['x', 'y']);
    controller.dispose();
  });

  test('upsert adds optimistically and persists', () async {
    final sync = FakeMapLocationSyncService();
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.upsert(_loc('a'));

    expect(controller.items.single.id, 'a');
    expect(sync.upserts.single.id, 'a');
    controller.dispose();
  });

  test('delete removes optimistically', () async {
    final sync = FakeMapLocationSyncService();
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();
    await controller.upsert(_loc('a'));
    await controller.upsert(_loc('b'));

    await controller.delete('a');

    expect(controller.items.map((i) => i.id), ['b']);
    expect(sync.deletes.single, 'a');
    controller.dispose();
  });

  test('locationsForMap filters by map type', () async {
    final sync = FakeMapLocationSyncService();
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(),
      syncService: sync,
    );
    await controller.bootstrap();
    await controller.upsert(_loc('lab-1', mapType: MapType.lab));
    await controller.upsert(_loc('pit-1', mapType: MapType.pit));

    expect(controller.locationsForMap(MapType.lab).length, 1);
    expect(controller.locationsForMap(MapType.pit).length, 1);
    expect(controller.locationsForMap(MapType.lab).single.id, 'lab-1');
    controller.dispose();
  });

  test(
    'stale-stream guard: emit after sign-out does not change items',
    () async {
      final auth = FakeSpectrumAuthService(initialUser: _signedInUser);
      final sync = FakeMapLocationSyncService();
      final controller = MapLocationController(
        authService: auth,
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emit([_loc('x')]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.items.map((i) => i.id), ['x']);

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      sync.emit([_loc('y')]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.items.map((i) => i.id), ['x']);
      controller.dispose();
    },
  );

  test('bootstrap is idempotent', () async {
    final sync = FakeMapLocationSyncService();
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await Future.wait([controller.bootstrap(), controller.bootstrap()]);

    sync.emit([_loc('x')]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.items.map((i) => i.id), ['x']);
    controller.dispose();
  });

  test('a stream error keeps the last items and does not crash', () async {
    final sync = FakeMapLocationSyncService();
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    await controller.bootstrap();

    sync.emit([_loc('x')]);
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
      logged.where(
        (m) => m.contains('MapLocationController sync stream error'),
      ),
      isNotEmpty,
    );
    controller.dispose();
  });

  test('disposing while bootstrap is in flight does not throw', () async {
    final sync = FakeMapLocationSyncService();
    final controller = MapLocationController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );

    // Do not await: dispose lands while bootstrap is still reading the cache.
    final booting = controller.bootstrap();
    controller.dispose();

    await expectLater(booting, completes);
  });
}
