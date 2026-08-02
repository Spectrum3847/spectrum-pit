import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/inventory_item.dart';
import 'inventory_sync_service.dart';

class DesktopInventorySyncService implements InventorySyncService {
  DesktopInventorySyncService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _firestore = firestore,
       _pollInterval = pollInterval;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  @override
  Future<List<InventoryItem>> fetchAll() async {
    final docs = await _firestore.listDocuments('inventoryItems');
    return docs.map((d) => InventoryItem.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(InventoryItem item) async {
    await _firestore.setDocument('inventoryItems/${item.id}', item.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.deleteDocument('inventoryItems/$id');
  }

  @override
  Stream<List<InventoryItem>> streamAll() async* {
    String? last;
    while (true) {
      List<InventoryItem>? items;
      try {
        final docs = await _firestore.listDocuments('inventoryItems');
        items = docs.map((d) => InventoryItem.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (_) {}
      if (items != null) {
        final fingerprint = items
            .map(
              (i) =>
                  '${i.id}:${i.name}:${i.labLocation}:${i.pitLocation}:'
                  '${i.mapRef ?? ''}:${i.status.name}:'
                  '${i.updatedAt.toIso8601String()}',
            )
            .join('|');
        if (fingerprint != last) {
          last = fingerprint;
          yield items;
        }
      }
      await Future<void>.delayed(_pollInterval);
    }
  }
}
