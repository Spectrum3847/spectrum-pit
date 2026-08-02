import 'dart:async';

import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/services/inventory_sync_service.dart';

class FakeInventorySyncService implements InventorySyncService {
  final Map<String, InventoryItem> _items = {};
  final StreamController<List<InventoryItem>> _controller =
      StreamController<List<InventoryItem>>.broadcast();

  // Recorded write calls, for assertions.
  final List<InventoryItem> upserts = [];
  final List<String> deletes = [];

  /// Set to make the next [upsert] or [delete] call fail, simulating an
  /// offline or auth-expired sync write.
  Object? failWith;

  // Fires once: the doc above promises the NEXT write fails, so clear it as it
  // throws. Retaining it would fail every later write and make a recovery path
  // impossible to test.
  void _throwIfConfigured() {
    final failure = failWith;
    if (failure == null) return;
    failWith = null;
    throw failure;
  }

  /// Push a snapshot to simulate a realtime emission (used in tests).
  void emit(List<InventoryItem> items) => _controller.add(items);

  /// Push a stream error to simulate a failed subscription (used in tests).
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<List<InventoryItem>> fetchAll() async => _items.values.toList();

  @override
  Future<void> upsert(InventoryItem item) async {
    _throwIfConfigured();
    upserts.add(item);
    _items[item.id] = item;
  }

  @override
  Future<void> delete(String id) async {
    _throwIfConfigured();
    deletes.add(id);
    _items.remove(id);
  }

  @override
  Stream<List<InventoryItem>> streamAll() => _controller.stream;
}
