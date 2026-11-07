import 'dart:js_interop';
import 'dart:typed_data';

import 'indexed_db_support.dart';
import 'map_diagram_blob_store.dart';

MapDiagramBlobStore createMapDiagramBlobStore() =>
    IndexedDbMapDiagramBlobStore();

class IndexedDbMapDiagramBlobStore implements MapDiagramBlobStore {
  IndexedDbMapDiagramBlobStore()
    : _handle = IndexedDbDatabaseHandle(_databaseName, [_storeName]);

  static const String _databaseName = 'spectrumpit_map_diagrams';
  static const String _storeName = 'diagrams';

  final IndexedDbDatabaseHandle _handle;

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final store = await _handle.store('readonly');
      final result = await completeIndexedDbRequest(store.get(key.toJS));
      final record = _validate(result);
      if (record == null) return null;
      return (record.bytes as JSUint8Array).toDart;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final store = await _handle.store('readwrite');
    await completeIndexedDbRequest(
      store.put(_DiagramRecord(bytes: bytes.toJS), key.toJS),
    );
  }

  @override
  Future<void> delete(String key) async {
    try {
      final store = await _handle.store('readwrite');
      await completeIndexedDbRequest(store.delete(key.toJS));
    } catch (_) {}
  }

  static _DiagramRecord? _validate(JSAny? value) {
    if (value == null || !value.isA<JSObject>()) return null;
    final record = value as _DiagramRecord;
    if (!record.bytes.isA<JSUint8Array>()) return null;
    return record;
  }
}

extension type _DiagramRecord._(JSObject _) implements JSObject {
  external factory _DiagramRecord({required JSUint8Array bytes});

  external JSAny? get bytes;
}
