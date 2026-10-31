// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';

import '../support/fake_inventory_sync_service.dart';
import '../support/fake_spectrum_auth_service.dart';
import 'pit_cache_bench.dart' show inventoryItem;

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold sync: empty device receives one full snapshot', () async {
    for (final n in <int>[100, 250, 500, 1000]) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final sync = FakeInventorySyncService();
      final controller = InventoryController(
        authService: FakeSpectrumAuthService(initialUser: _signedInUser),
        syncService: sync,
      );
      await controller.bootstrap();

      final remote = <InventoryItem>[
        for (var i = 0; i < n; i++) inventoryItem(i),
      ];
      final sw = Stopwatch()..start();
      sync.emit(remote);
      await Future<void>.delayed(Duration.zero);
      sw.stop();
      print(
        'cold sync N=$n: ${sw.elapsedMilliseconds} ms to drain '
        '(${controller.items.length} items)',
      );
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('steady state: unchanged snapshot every poll', () async {
    for (final n in <int>[100, 250, 500, 1000]) {
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

      final remote = <InventoryItem>[
        for (var i = 0; i < n; i++) inventoryItem(i),
      ];
      final sw = Stopwatch()..start();
      const iters = 10;
      for (var i = 0; i < iters; i++) {
        sync.emit(remote);
        await Future<void>.delayed(Duration.zero);
      }
      sw.stop();
      print(
        'steady N=$n: bootstrap=${swBoot.elapsedMilliseconds} ms, '
        'unchanged-snapshot=${(sw.elapsedMicroseconds / 1000 / iters).toStringAsFixed(2)} ms',
      );
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
