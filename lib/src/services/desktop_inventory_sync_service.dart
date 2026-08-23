import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_polling.dart';

import '../models/inventory_item.dart';
import 'inventory_sync_service.dart';

class DesktopInventorySyncService implements InventorySyncService {
  DesktopInventorySyncService({
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    this._onPollError,
  });

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

  @override
  Future<List<InventoryItem>> fetchAll() async {
    final docs = await _firestore.listDocuments('inventoryItems');
    return docs.map((d) => InventoryItem.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(InventoryItem item) async {
    await _firestore.setDocument('inventoryItems/${item.id}', {
      ...item.toJson(),
      'updatedAtTs': item.updatedAt.toUtc(),
    });
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.deleteDocument('inventoryItems/$id');
  }

  @override
  Stream<List<InventoryItem>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (true) {
      List<InventoryItem>? items;
      try {
        final docs = await _firestore.listDocuments('inventoryItems');
        items = docs.map((d) => InventoryItem.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        consecutiveFailures++;
        try {
          _onPollError?.call(error);
        } catch (_) {}
        debugPrint('inventoryItems poll failed: $error');
      }
      if (items != null) {
        consecutiveFailures = 0;
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
      await Future<void>.delayed(
        pollDelayFor(_pollInterval, consecutiveFailures),
      );
    }
  }
}
