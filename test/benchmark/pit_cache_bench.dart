// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';

import '../support/fake_inventory_sync_service.dart';
import '../support/fake_spectrum_auth_service.dart';

InventoryItem inventoryItem(int i) => InventoryItem(
  id: 'item-$i',
  name: 'Tool $i',
  labLocation: 'Shelf ${i % 12}',
  pitLocation: 'Bin ${i % 6}',
  mapRef: i.isEven ? 'map-loc-$i' : null,
  status: InventoryStatus.values[i % InventoryStatus.values.length],
  updatedAt: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
);

PackingRecord packingRecord(int i) => PackingRecord(
  id: 'record-$i',
  itemId: 'item-$i',
  packingStatus: PackingStatus.values[i % PackingStatus.values.length],
  photoRef: i.isEven ? 'photo-$i' : null,
  updatedAt: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
);

BorrowRecord borrowRecord(int i) => BorrowRecord(
  id: 'borrow-$i',
  itemId: 'item-$i',
  toolName: 'Drill $i',
  teamName: 'Team $i',
  teamNumber: 1000 + (i % 40),
  competition: 'comp-2026',
  contact: 'contact-$i@example.com',
  checkedOutAt: DateTime.utc(2026, 3, 1),
  estimatedReturn: DateTime.utc(2026, 3, 4),
  returned: i.isOdd,
  updatedAt: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
);

MapLocation mapLocation(int i) => MapLocation(
  id: 'loc-$i',
  name: 'Pin $i',
  mapType: MapType.values[i % MapType.values.length],
  x: (i % 100) / 100,
  y: ((i * 7) % 100) / 100,
  inventoryItemId: i.isEven ? 'item-$i' : null,
  updatedAt: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
);

PitShift pitShift(int i) => PitShift(
  id: 'shift-$i',
  label: 'Shift $i',
  kind: ShiftKind.values[i % ShiftKind.values.length],
  competition: 'comp-2026',
  assignedUids: <String>['uid-${i % 8}', 'uid-${(i + 1) % 8}'],
  assignedNames: <String>['Student ${i % 8}', 'Student ${(i + 1) % 8}'],
  startMatch: i % 20,
  endMatch: (i % 20) + 5,
  notes: 'Cover the trailer door.',
  updatedAt: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
);

double ms(Stopwatch s, int iters) => s.elapsedMicroseconds / 1000 / iters;

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('measurements', () async {
    void report(String s) => print(s);

    report(
      'InventoryItem encoded: ${jsonEncode(inventoryItem(1).toJson()).length} bytes',
    );
    report(
      'PackingRecord encoded: ${jsonEncode(packingRecord(1).toJson()).length} bytes',
    );
    report(
      'BorrowRecord encoded: ${jsonEncode(borrowRecord(1).toJson()).length} bytes',
    );
    report(
      'MapLocation encoded: ${jsonEncode(mapLocation(1).toJson()).length} bytes',
    );
    report(
      'PitShift encoded: ${jsonEncode(pitShift(1).toJson()).length} bytes',
    );

    for (final n in <int>[50, 100, 250, 500, 1000]) {
      final cached = jsonEncode([
        for (var i = 0; i < n; i++)
          {...inventoryItem(i).toJson(), 'id': 'item-$i'},
      ]);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pit_inventory_cache': cached,
      });
      final sync = FakeInventorySyncService();
      final controller = InventoryController(
        authService: FakeSpectrumAuthService(initialUser: _signedInUser),
        syncService: sync,
      );

      final swBoot = Stopwatch()..start();
      await controller.bootstrap();
      swBoot.stop();

      const iters = 20;
      final sw = Stopwatch()..start();
      for (var i = 0; i < iters; i++) {
        await controller.upsert(inventoryItem(i % n));
      }
      sw.stop();

      report(
        'N=$n blob=${(cached.length / 1024).round()}KB  '
        'bootstrap(cache load)=${swBoot.elapsedMilliseconds} ms  '
        'upsert(update)=${ms(sw, iters).toStringAsFixed(2)} ms/call',
      );
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
