import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_diagram_sync_service.dart';

class FakeMapDiagramSyncService implements MapDiagramSyncService {
  FakeMapDiagramSyncService({
    String? readKeyValue,
    Object? readFailure,
    Object? writeFailure,
    Object? clearFailure,
    this.onWriteKey,
  }) : _readFailure = readFailure,
       _writeFailure = writeFailure,
       _clearFailure = clearFailure {
    if (readKeyValue != null) {
      for (final mapType in MapType.values) {
        _readKeyValues[mapType] = readKeyValue;
      }
    }
  }

  final Map<MapType, String?> _readKeyValues = <MapType, String?>{};
  final Object? _readFailure;
  final Object? _writeFailure;
  final Object? _clearFailure;

  final Future<void> Function(MapType mapType, String key)? onWriteKey;

  final List<({MapType mapType, String key})> writeCalls = [];

  final List<MapType> clearCalls = [];

  @override
  Future<String?> readKey(MapType mapType) async {
    if (_readFailure != null) throw _readFailure;
    return _readKeyValues[mapType];
  }

  @override
  Future<void> writeKey(MapType mapType, String key) async {
    await onWriteKey?.call(mapType, key);
    writeCalls.add((mapType: mapType, key: key));
    if (_writeFailure != null) throw _writeFailure;

    _readKeyValues[mapType] = key;
  }

  @override
  Future<void> clearKey(MapType mapType) async {
    clearCalls.add(mapType);
    if (_clearFailure != null) throw _clearFailure;

    _readKeyValues[mapType] = null;
  }
}
