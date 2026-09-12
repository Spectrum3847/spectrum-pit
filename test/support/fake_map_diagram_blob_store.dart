import 'dart:typed_data';

import 'package:spectrumpit/src/services/map_diagram_blob_store.dart';

class FakeMapDiagramBlobStore implements MapDiagramBlobStore {
  final Map<String, Uint8List> blobs = <String, Uint8List>{};
  final List<String> calls = <String>[];

  Object? writeFailure;

  @override
  Future<Uint8List?> read(String key) async {
    calls.add('read:$key');
    return blobs[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    calls.add('write:$key');
    final failure = writeFailure;
    if (failure != null) {
      writeFailure = null;
      throw failure;
    }
    blobs[key] = bytes;
  }

  @override
  Future<void> delete(String key) async {
    calls.add('delete:$key');
    blobs.remove(key);
  }
}

class ThrowingDeleteMapDiagramBlobStore implements MapDiagramBlobStore {
  final Map<String, Uint8List> blobs = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async => blobs[key];

  @override
  Future<void> write(String key, Uint8List bytes) async {
    blobs[key] = bytes;
  }

  @override
  Future<void> delete(String key) async {
    throw StateError('delete should never be called directly by a caller');
  }
}
