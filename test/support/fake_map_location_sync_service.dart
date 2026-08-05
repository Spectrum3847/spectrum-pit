import 'dart:async';

import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_location_sync_service.dart';

class FakeMapLocationSyncService implements MapLocationSyncService {
  final Map<String, MapLocation> _items = {};
  final StreamController<List<MapLocation>> _controller =
      StreamController<List<MapLocation>>.broadcast();

  // Recorded write calls, for assertions.
  final List<MapLocation> upserts = [];
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
  void emit(List<MapLocation> items) => _controller.add(items);

  /// Publish a stream error, like the real backend does on a permission-denied
  /// read.
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
