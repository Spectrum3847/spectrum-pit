import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_polling.dart';
import 'in_flight_local_writes.dart';

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

  final InFlightLocalWrites<InventoryItem> _inFlightWrites =
      InFlightLocalWrites<InventoryItem>();

  @override
  Future<List<InventoryItem>> fetchAll() async {
    final docs = await _firestore.listDocuments('inventoryItems');
    return docs.map((d) => InventoryItem.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(InventoryItem item) async {
    final token = _inFlightWrites.beginPush(item.id, item);
    try {
      await _firestore.setDocument('inventoryItems/${item.id}', {
        ...item.toJson(),
        'updatedAtTs': item.updatedAt.toUtc(),
      });

      _inFlightWrites.recordPush(item.id, item, token);
    } finally {
      _inFlightWrites.endWrite(item.id, token);
    }
  }

  @override
  Future<void> delete(String id) async {
    final token = _inFlightWrites.beginDelete(id);
    try {
      await _firestore.deleteDocument('inventoryItems/$id');

      _inFlightWrites.recordDelete(id, token);
    } finally {
      _inFlightWrites.endWrite(id, token);
    }
  }

  @override
  Stream<List<InventoryItem>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (true) {
      List<InventoryItem>? items;

      final window = _inFlightWrites.beginFetch();
      try {
        final docs = await _firestore.listDocuments('inventoryItems');
        final fetched = <String, InventoryItem>{
          for (final d in docs) d.id: InventoryItem.fromJson(d.id, d.fields),
        };
        items = _inFlightWrites.resolve(window, fetched).values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        _inFlightWrites.abandonFetch(window);
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
