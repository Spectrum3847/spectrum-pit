import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'map_diagram_blob_store.dart';

MapDiagramBlobStore createMapDiagramBlobStore() => FileMapDiagramBlobStore();

class FileMapDiagramBlobStore implements MapDiagramBlobStore {
  @override
  Future<Uint8List?> read(String key) async {
    try {
      final file = await _fileFor(key);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final file = await _fileFor(key);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = await _fileFor(key);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  Future<File> _fileFor(String key) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$key');
  }
}
