import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_diagram_sync_service.dart';

/// Fake [MapDiagramSyncService] for tests: no Firestore, no network. Seeds
/// [readKeyValue] for the read path; set [readFailure] to make [readKey]
/// throw (simulating an offline / auth-expired read). [writeKey] records every
/// call on [writeCalls] and optionally throws ([writeFailure]) or notifies an
/// [onWriteKey] callback before returning, so a test can inspect ordering
/// relative to local persistence.
class FakeMapDiagramSyncService implements MapDiagramSyncService {
  FakeMapDiagramSyncService({
    String? readKeyValue,
    Object? readFailure,
    Object? writeFailure,
    Object? clearFailure,
    this.onWriteKey,
  }) : _readKeyValue = readKeyValue,
       _readFailure = readFailure,
       _writeFailure = writeFailure,
       _clearFailure = clearFailure;

  String? _readKeyValue;
  final Object? _readFailure;
  final Object? _writeFailure;
  final Object? _clearFailure;

  /// Invoked by [writeKey] before it records the call and before it returns,
  /// so a test can snapshot state (e.g. the SharedPreferences R2-key pointer
  /// or the cache directory) at the exact moment the remote write runs.
  final Future<void> Function(MapType mapType, String key)? onWriteKey;

  // Recorded write calls (most recent last), for assertions.
  final List<({MapType mapType, String key})> writeCalls = [];

  /// Every map type passed to [clearKey], for assertions.
  final List<MapType> clearCalls = [];

  @override
  Future<String?> readKey(MapType mapType) async {
    if (_readFailure != null) throw _readFailure;
    return _readKeyValue;
  }

  @override
  Future<void> writeKey(MapType mapType, String key) async {
    await onWriteKey?.call(mapType, key);
    writeCalls.add((mapType: mapType, key: key));
    if (_writeFailure != null) throw _writeFailure;
    // Store the pointer, so a later readKey reflects the write. clearKey
    // already did the mirror of this; without it the fake reported a stale key
    // after a successful write and no test could catch a read-after-write
    // mistake (#169). A failed write deliberately does not update it.
    _readKeyValue = key;
  }

  @override
  Future<void> clearKey(MapType mapType) async {
    clearCalls.add(mapType);
    if (_clearFailure != null) throw _clearFailure;
    // Clear the stored pointer so a later readKey reflects the cleared state,
    // rather than leaving diagramFor to discover a deleted object by 404.
    _readKeyValue = null;
  }
}
