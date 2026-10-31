import 'dart:async';

import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_location_sync_service.dart';

class FakeMapLocationSyncService implements MapLocationSyncService {
  final Map<String, MapLocation> _items = {};
  final StreamController<List<MapLocation>> _controller =
      StreamController<List<MapLocation>>.broadcast();

  final List<MapLocation> upserts = [];
  final List<String> deletes = [];

  Object? failWith;

  void _throwIfConfigured() {
    final failure = failWith;
    if (failure == null) return;
    failWith = null;
    throw failure;
  }

  void emit(List<MapLocation> items) => _controller.add(items);

  void emitError(Object error) => _controller.addError(error);

  @override
  Future<List<MapLocation>> fetchAll() async => _items.values.toList();

  @override
  Future<void> upsert(MapLocation location) async {
    _throwIfConfigured();
    upserts.add(location);
    _items[location.id] = location;
  }

  @override
  Future<void> delete(String id) async {
    _throwIfConfigured();
    deletes.add(id);
    _items.remove(id);
  }

  @override
  Stream<List<MapLocation>> streamAll() => _controller.stream;
}
