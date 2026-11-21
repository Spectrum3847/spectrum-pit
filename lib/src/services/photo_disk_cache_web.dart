import 'dart:js_interop';

import 'package:flutter/foundation.dart' show Uint8List, debugPrint;

import 'indexed_db_support.dart';
import 'lru_byte_cache.dart';
import 'photo_disk_cache.dart';

PhotoDiskCache createPhotoDiskCache() => IndexedDbPhotoDiskCache();

class IndexedDbPhotoDiskCache implements PhotoDiskCache {
  IndexedDbPhotoDiskCache({this.maxBytes = PhotoDiskCache.defaultMaxBytes})
    : _handle = IndexedDbDatabaseHandle(_databaseName, [
        _blobStoreName,
        _metaStoreName,
      ], version: _databaseVersion);

  static const String _databaseName = 'spectrumpit_photo_cache';
  static const String _blobStoreName = 'blobs';
  static const String _metaStoreName = 'meta';

  static const int _databaseVersion = 2;

  final int maxBytes;
  final IndexedDbDatabaseHandle _handle;

  @override
  bool get isSupported => true;

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final txn = await _handle.transaction([
        _blobStoreName,
        _metaStoreName,
      ], 'readwrite');
      final blobs = txn.objectStore(_blobStoreName);
      final metaStore = txn.objectStore(_metaStoreName);
      final blob = _validateBlob(
        await completeIndexedDbRequest(blobs.get(key.toJS)),
      );
      if (blob == null) return null;
      final bytes = (blob.bytes as JSUint8Array).toDart;
      final meta = _validateMeta(
        await completeIndexedDbRequest(metaStore.get(key.toJS)),
      );
      final size = meta?.sizeBytes.toInt() ?? bytes.length;
      await completeIndexedDbRequest(
        metaStore.put(
          _meta(size, DateTime.now().millisecondsSinceEpoch),
          key.toJS,
        ),
      );
      return bytes;
    } catch (error) {
      debugPrint('PhotoDiskCache read failed for $key: $error');
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    try {
      final txn = await _handle.transaction([
        _blobStoreName,
        _metaStoreName,
      ], 'readwrite');
      await completeIndexedDbRequest(
        txn.objectStore(_blobStoreName).put(_blob(bytes), key.toJS),
      );
      await completeIndexedDbRequest(
        txn
            .objectStore(_metaStoreName)
            .put(
              _meta(bytes.length, DateTime.now().millisecondsSinceEpoch),
              key.toJS,
            ),
      );
    } catch (error) {
      debugPrint('PhotoDiskCache write failed for $key: $error');
      return;
    }
    await _trim();
  }

  @override
  Future<void> remove(String key) async {
    try {
      final txn = await _handle.transaction([
        _blobStoreName,
        _metaStoreName,
      ], 'readwrite');

      await completeIndexedDbRequest(
        txn.objectStore(_blobStoreName).delete(key.toJS),
      );
      await completeIndexedDbRequest(
        txn.objectStore(_metaStoreName).delete(key.toJS),
      );
    } catch (error) {
      debugPrint('PhotoDiskCache remove failed for $key: $error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final txn = await _handle.transaction([
        _blobStoreName,
        _metaStoreName,
      ], 'readwrite');
      await completeIndexedDbRequest(txn.objectStore(_blobStoreName).clear());
      await completeIndexedDbRequest(txn.objectStore(_metaStoreName).clear());
    } catch (error) {
      debugPrint('PhotoDiskCache clear failed: $error');
    }
  }

  @override
  Future<int> currentBytes() async {
    try {
      final metas = await _allMeta();
      return metas.fold<int>(0, (sum, meta) => sum + meta.sizeBytes);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _trim() async {
    try {
      final metas = await _allMeta();
      final evict = keysToEvict(metas, maxBytes);
      if (evict.isEmpty) return;
      final txn = await _handle.transaction([
        _blobStoreName,
        _metaStoreName,
      ], 'readwrite');
      final blobs = txn.objectStore(_blobStoreName);
      final metaStore = txn.objectStore(_metaStoreName);
      for (final key in evict) {
        await completeIndexedDbRequest(blobs.delete(key.toJS));
        await completeIndexedDbRequest(metaStore.delete(key.toJS));
      }
    } catch (error) {
      debugPrint('PhotoDiskCache trim failed: $error');
    }
  }

  Future<List<ByteRecordMeta>> _allMeta() async {
    final txn = await _handle.transaction([
      _blobStoreName,
      _metaStoreName,
    ], 'readwrite');
    final blobs = txn.objectStore(_blobStoreName);
    final metaStore = txn.objectStore(_metaStoreName);

    final blobKeysResult =
        await completeIndexedDbRequest(blobs.getAllKeys()) as JSArray<JSAny?>;
    final liveKeys = <String>{
      for (final key in blobKeysResult.toDart)
        if (key.isA<JSString>()) (key as JSString).toDart,
    };

    final metaKeysResult = await completeIndexedDbRequest(
      metaStore.getAllKeys(),
    ) as JSArray<JSAny?>;
    final metaValuesResult =
        await completeIndexedDbRequest(metaStore.getAll()) as JSArray<JSAny?>;
    final metaKeys = metaKeysResult.toDart;
    final metaValues = metaValuesResult.toDart;
    final metaByKey = <String, ByteRecordMeta>{};
    for (var i = 0; i < metaKeys.length && i < metaValues.length; i++) {
      final keyJs = metaKeys[i];
      if (!keyJs.isA<JSString>()) continue;
      final key = (keyJs as JSString).toDart;
      if (!liveKeys.contains(key)) continue;
      final record = _validateMeta(metaValues[i]);
      if (record == null) continue;
      metaByKey[key] = ByteRecordMeta(
        key: key,
        sizeBytes: record.sizeBytes.toInt(),
        lastReadMillis: record.lastReadMillis.toInt(),
      );
    }

    final metas = <ByteRecordMeta>[];
    for (final key in liveKeys) {
      final existing = metaByKey[key];
      if (existing != null) {
        metas.add(existing);
        continue;
      }

      final blob = _validateBlob(
        await completeIndexedDbRequest(blobs.get(key.toJS)),
      );
      final size = blob == null
          ? 0
          : (blob.bytes as JSUint8Array).toDart.length;
      await completeIndexedDbRequest(metaStore.put(_meta(size, 0), key.toJS));
      metas.add(ByteRecordMeta(key: key, sizeBytes: size, lastReadMillis: 0));
    }
    return metas;
  }

  static _BlobRecord _blob(Uint8List bytes) => _BlobRecord(bytes: bytes.toJS);

  static _MetaRecord _meta(int sizeBytes, int lastReadMillis) =>
      _MetaRecord(sizeBytes: sizeBytes, lastReadMillis: lastReadMillis);

  static _BlobRecord? _validateBlob(JSAny? value) {
    if (value == null || !value.isA<JSObject>()) return null;
    final record = value as _BlobRecord;
    if (!record.bytes.isA<JSUint8Array>()) return null;
    return record;
  }

  static _MetaRecord? _validateMeta(JSAny? value) {
    if (value == null || !value.isA<JSObject>()) return null;
    return value as _MetaRecord;
  }
}

extension type _BlobRecord._(JSObject _) implements JSObject {
  external factory _BlobRecord({required JSUint8Array bytes});

  external JSAny? get bytes;
}

extension type _MetaRecord._(JSObject _) implements JSObject {
  external factory _MetaRecord({
    required int sizeBytes,
    required int lastReadMillis,
  });

  external num get sizeBytes;
  external num get lastReadMillis;
}
