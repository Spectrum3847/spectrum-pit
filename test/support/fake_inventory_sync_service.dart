import 'dart:async';

import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/services/inventory_sync_service.dart';

class FakeInventorySyncService implements InventorySyncService {
  final Map<String, InventoryItem> _items = {};
  final StreamController<List<InventoryItem>> _controller =
      StreamController<List<InventoryItem>>.broadcast();

  final List<InventoryItem> upserts = [];
  final List<String> deletes = [];

  Object? failWith;

  final List<Object?> failSchedule = [];

  Completer<void>? holdUpsert;

  final List<String> serverOps = [];

  Iterable<String> get storedIds => _items.keys;

  void _throwIfConfigured() {
    if (failSchedule.isNotEmpty) {
      final failure = failSchedule.removeAt(0);
      if (failure != null) throw failure;
      return;
    }
    final failure = failWith;
    if (failure == null) return;
    failWith = null;
    throw failure;
  }

  void emit(List<InventoryItem> items) => _controller.add(items);

  void emitError(Object error) => _controller.addError(error);

  @override
  Future<List<InventoryItem>> fetchAll() async => _items.values.toList();

  @override
  Future<void> upsert(InventoryItem item) async {
    _throwIfConfigured();
    upserts.add(item);
    final hold = holdUpsert;
    if (hold != null) await hold.future;
    serverOps.add('upsert:${item.id}');
    _items[item.id] = item;
  }

  @override
  Future<void> delete(String id) async {
    _throwIfConfigured();
    deletes.add(id);
    serverOps.add('delete:$id');
    _items.remove(id);
  }

  @override
  Stream<List<InventoryItem>> streamAll() => _controller.stream;
}
