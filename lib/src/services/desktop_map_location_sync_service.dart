import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_polling.dart';
import 'in_flight_local_writes.dart';

import '../models/map_location.dart';
import 'map_location_sync_service.dart';

class DesktopMapLocationSyncService implements MapLocationSyncService {
  DesktopMapLocationSyncService({
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    this._onPollError,
  });

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

  final InFlightLocalWrites<MapLocation> _inFlightWrites =
      InFlightLocalWrites<MapLocation>();

  @override
  Future<List<MapLocation>> fetchAll() async {
    final docs = await _firestore.listDocuments('mapLocations');
    return docs.map((d) => MapLocation.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(MapLocation location) async {
    final token = _inFlightWrites.beginPush(location.id, location);
    try {
      await _firestore.setDocument('mapLocations/${location.id}', {
        ...location.toJson(),
        'updatedAtTs': location.updatedAt.toUtc(),
      });

      _inFlightWrites.recordPush(location.id, location, token);
    } finally {
      _inFlightWrites.endWrite(location.id, token);
    }
  }

  @override
  Future<void> delete(String id) async {
    final token = _inFlightWrites.beginDelete(id);
    try {
      await _firestore.deleteDocument('mapLocations/$id');

      _inFlightWrites.recordDelete(id, token);
    } finally {
      _inFlightWrites.endWrite(id, token);
    }
  }

  @override
  Stream<List<MapLocation>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (true) {
      List<MapLocation>? items;

      final window = _inFlightWrites.beginFetch();
      try {
        final docs = await _firestore.listDocuments('mapLocations');
        final fetched = <String, MapLocation>{
          for (final d in docs) d.id: MapLocation.fromJson(d.id, d.fields),
        };
        items = _inFlightWrites.resolve(window, fetched).values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        _inFlightWrites.abandonFetch(window);
        consecutiveFailures++;
        try {
          _onPollError?.call(error);
        } catch (_) {}
        debugPrint('mapLocations poll failed: $error');
      }
      if (items != null) {
        consecutiveFailures = 0;
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
      await Future<void>.delayed(
        pollDelayFor(_pollInterval, consecutiveFailures),
      );
    }
  }
}
