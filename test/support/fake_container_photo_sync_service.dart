import 'package:spectrumpit/src/services/container_photo_sync_service.dart';

class FakeContainerPhotoSyncService implements ContainerPhotoSyncService {
  FakeContainerPhotoSyncService({
    Map<String, String?> seed = const <String, String?>{},
    Object? readFailure,
    Object? writeFailure,
    Object? clearFailure,
    this.onWriteKey,
  }) : _readKeyValues = {...seed},
       _readFailure = readFailure,
       _writeFailure = writeFailure,
       _clearFailure = clearFailure;

  final Map<String, String?> _readKeyValues;
  final Object? _readFailure;
  final Object? _writeFailure;
  final Object? _clearFailure;

  final Future<void> Function(String location, String key)? onWriteKey;

  final List<({String location, String key})> writeCalls = [];

  final List<String> readCalls = [];

  final List<String> clearCalls = [];

  @override
  Future<String?> readKey(String location) async {
    readCalls.add(location);
    if (_readFailure != null) throw _readFailure;
    return _readKeyValues[location];
  }

  @override
  Future<void> writeKey(String location, String key) async {
    await onWriteKey?.call(location, key);
    writeCalls.add((location: location, key: key));
    if (_writeFailure != null) throw _writeFailure;

    _readKeyValues[location] = key;
  }

  @override
  Future<void> clearKey(String location) async {
    clearCalls.add(location);
    if (_clearFailure != null) throw _clearFailure;

    _readKeyValues[location] = null;
  }
}
