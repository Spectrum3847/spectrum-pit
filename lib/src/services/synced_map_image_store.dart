import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show MemoryImage, Size;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_location.dart';
import 'map_diagram_blob_store.dart';
import 'map_diagram_blob_store_web.dart'
    if (dart.library.io) 'map_diagram_blob_store_io.dart'
    as blob_store;
import 'map_diagram_sync_service.dart';
import 'map_image_store.dart';
import 'photo_service.dart';

class SyncedMapImageStore implements MapImageStore {
  SyncedMapImageStore({
    required this.photoService,
    required this.diagramSync,
    MapDiagramBlobStore? blobStore,
  }) : _blobs = blobStore ?? blob_store.createMapDiagramBlobStore();

  static const String _prefsR2Key = 'pit_map_diagram_r2key_';
  static const String _prefsFile = 'pit_map_diagram_file_';

  final PhotoService photoService;
  final MapDiagramSyncService diagramSync;
  final MapDiagramBlobStore _blobs;

  @override
  bool get isSupported => true;

  @override
  Future<MapDiagram?> diagramFor(MapType mapType) async {
    final prefs = await SharedPreferences.getInstance();
    String? key;
    try {
      key = await diagramSync.readKey(mapType);
    } catch (_) {
      return _cachedDiagram(mapType);
    }
    if (key == null) return null;
    final cachedKey = prefs.getString(_prefsKey(mapType, _prefsR2Key));
    if (cachedKey == key) {
      final cached = await _cachedBytes(mapType);
      if (cached != null) return _diagramFromBytes(cached);
    }
    try {
      final bytes = await photoService.fetch(key);
      if (bytes == null) return null;
      await _saveToCache(mapType, key, bytes);
      await prefs.setString(_prefsKey(mapType, _prefsR2Key), key);
      return await _diagramFromBytes(bytes);
    } catch (_) {
      return _cachedDiagram(mapType);
    }
  }

  Future<MapDiagram?> _cachedDiagram(MapType mapType) async {
    final bytes = await _cachedBytes(mapType);
    if (bytes == null) return null;
    return _diagramFromBytes(bytes);
  }

  @override
  Future<MapDiagram?> pickDiagram(MapType mapType) async {
    final picked = await photoService.pickImage();
    if (picked == null) return null;
    final bytes = picked.bytes;
    final key = await photoService.upload(picked);

    await diagramSync.writeKey(mapType, key);
    final prefs = await SharedPreferences.getInstance();
    await _saveToCache(mapType, key, bytes);
    await prefs.setString(_prefsKey(mapType, _prefsR2Key), key);
    return _diagramFromBytes(bytes);
  }

  @override
  Future<void> clearDiagram(MapType mapType) async {
    String? key;
    try {
      key = await diagramSync.readKey(mapType);
    } catch (_) {}
    key ??= (await SharedPreferences.getInstance()).getString(
      _prefsKey(mapType, _prefsR2Key),
    );

    var pointerCleared = false;
    Object? pointerFailure;
    StackTrace? pointerStackTrace;
    try {
      await diagramSync.clearKey(mapType);
      pointerCleared = true;
    } catch (error, stackTrace) {
      pointerFailure = error;
      pointerStackTrace = stackTrace;
    }
    if (pointerCleared && key != null && key.isNotEmpty) {
      try {
        await photoService.delete(key);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final filename = prefs.getString(_prefsKey(mapType, _prefsFile));
    if (filename != null && filename.isNotEmpty) {
      await _blobs.delete(filename);
    }
    await prefs.remove(_prefsKey(mapType, _prefsR2Key));
    await prefs.remove(_prefsKey(mapType, _prefsFile));
    if (pointerFailure != null) {
      Error.throwWithStackTrace(pointerFailure, pointerStackTrace!);
    }
  }

  Future<Uint8List?> _cachedBytes(MapType mapType) async {
    final prefs = await SharedPreferences.getInstance();
    final filename = prefs.getString(_prefsKey(mapType, _prefsFile));
    if (filename == null || filename.isEmpty) return null;
    return _blobs.read(filename);
  }

  Future<void> _saveToCache(
    MapType mapType,
    String key,
    Uint8List bytes,
  ) async {
    final ext = _extensionFromKey(key);
    final filename = 'diagram_${mapType.name}_$key.$ext';
    final prefs = await SharedPreferences.getInstance();
    final oldName = prefs.getString(_prefsKey(mapType, _prefsFile));

    await _blobs.write(filename, bytes);
    await prefs.setString(_prefsKey(mapType, _prefsFile), filename);
    if (oldName != null && oldName.isNotEmpty && oldName != filename) {
      try {
        await _blobs.delete(oldName);
      } catch (_) {}
    }
  }

  Future<MapDiagram?> _diagramFromBytes(Uint8List bytes) async {
    try {
      final size = await _decodeSize(bytes);
      return MapDiagram(image: MemoryImage(bytes), size: size);
    } catch (_) {
      return null;
    }
  }

  static Future<Size> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );

      frame.image.dispose();
      return size;
    } finally {
      codec.dispose();
    }
  }

  String _prefsKey(MapType mapType, String prefix) => '$prefix${mapType.name}';

  static String _extensionFromKey(String key) {
    final dot = key.lastIndexOf('.');
    return dot < 0 ? 'png' : key.substring(dot + 1);
  }
}
