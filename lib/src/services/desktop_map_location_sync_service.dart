import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/map_location.dart';
import 'map_location_sync_service.dart';

class DesktopMapLocationSyncService implements MapLocationSyncService {
  DesktopMapLocationSyncService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _firestore = firestore,
       _pollInterval = pollInterval;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  @override
  Future<List<MapLocation>> fetchAll() async {
    final docs = await _firestore.listDocuments('mapLocations');
    return docs.map((d) => MapLocation.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(MapLocation location) async {
    await _firestore.setDocument(
      'mapLocations/${location.id}',
      location.toJson(),
    );
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.deleteDocument('mapLocations/$id');
  }

  @override
  Stream<List<MapLocation>> streamAll() async* {
    String? last;
    while (true) {
      List<MapLocation>? items;
      try {
        final docs = await _firestore.listDocuments('mapLocations');
        items = docs.map((d) => MapLocation.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (_) {}
      if (items != null) {
        final fingerprint = items
            .map(
              (i) =>
                  '${i.id}:${i.name}:${i.mapType.name}:'
                  '${i.x}:${i.y}:${i.inventoryItemId ?? ''}:'
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
