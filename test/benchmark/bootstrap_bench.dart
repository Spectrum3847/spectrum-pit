// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/map_location_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';

import '../support/fake_borrow_sync_service.dart';
import '../support/fake_inventory_sync_service.dart';
import '../support/fake_map_location_sync_service.dart';
import '../support/fake_packing_sync_service.dart';
import '../support/fake_pit_shift_sync_service.dart';
import '../support/fake_spectrum_auth_service.dart';
import 'pit_cache_bench.dart'
    show borrowRecord, inventoryItem, mapLocation, packingRecord, pitShift;

const int kInventory = 300;
const int kPacking = 150;
const int kBorrow = 20;
const int kMapLocations = 300;
const int kShifts = 100;

Map<String, Object> seed() {
  Object blob(int n, Map<String, dynamic> Function(int) toJson, String prefix) {
    return jsonEncode([
      for (var i = 0; i < n; i++) {...toJson(i), 'id': '$prefix-$i'},
    ]);
  }

  return <String, Object>{
    'pit_inventory_cache': blob(
      kInventory,
      (i) => inventoryItem(i).toJson(),
      'item',
    ),
    'pit_packing_cache': blob(
      kPacking,
      (i) => packingRecord(i).toJson(),
      'record',
    ),
    'pit_borrow_cache': blob(
      kBorrow,
      (i) => borrowRecord(i).toJson(),
      'borrow',
    ),
    'pit_map_locations_cache': blob(
      kMapLocations,
      (i) => mapLocation(i).toJson(),
      'loc',
    ),
    'pit_shifts_cache': blob(kShifts, (i) => pitShift(i).toJson(), 'shift'),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('per-controller bootstrap, run the way app.dart runs them', () async {
    SharedPreferences.setMockInitialValues(seed());

    final inventory = InventoryController(
      authService: FakeSpectrumAuthService(),
      syncService: FakeInventorySyncService(),
    );
    final packing = PackingController(
      authService: FakeSpectrumAuthService(),
      syncService: FakePackingSyncService(),
    );
    final borrow = BorrowController(
      authService: FakeSpectrumAuthService(),
      syncService: FakeBorrowSyncService(),
    );
    final mapLocations = MapLocationController(
      authService: FakeSpectrumAuthService(),
      syncService: FakeMapLocationSyncService(),
    );
    final shifts = PitShiftController(
      authService: FakeSpectrumAuthService(),
      syncService: FakePitShiftSyncService(),
    );

    final results = <String, int>{};
    Future<void> timed(String name, Future<void> Function() bootstrap) async {
      final sw = Stopwatch()..start();
      await bootstrap();
      sw.stop();
      results[name] = sw.elapsedMilliseconds;
    }

    final swTotal = Stopwatch()..start();
    await Future.wait(<Future<void>>[
      timed('InventoryController ($kInventory items)', inventory.bootstrap),
      timed('PackingController ($kPacking records)', packing.bootstrap),
      timed('BorrowController ($kBorrow records)', borrow.bootstrap),
      timed(
        'MapLocationController ($kMapLocations pins)',
        mapLocations.bootstrap,
      ),
      timed('PitShiftController ($kShifts shifts)', shifts.bootstrap),
    ]);
    swTotal.stop();

    for (final c in [inventory, packing, borrow, mapLocations, shifts]) {
      c.dispose();
    }

    final ordered = results.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('--- bootstrap, all five controllers awaited concurrently');
    for (final e in ordered) {
      print('${e.value.toString().padLeft(5)} ms  ${e.key}');
    }
    print(
      'Future.wait total: ${swTotal.elapsedMilliseconds} ms, '
      'slowest sets the first frame: ${ordered.first.key}',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
