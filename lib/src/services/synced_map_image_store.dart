import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show FileImage, Size;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_location.dart';
import 'map_diagram_sync_service.dart';
import 'map_image_store.dart';
import 'photo_service.dart';

class SyncedMapImageStore implements MapImageStore {
  SyncedMapImageStore({required this.photoService, required this.diagramSync});

  static const String _prefsR2Key = 'pit_map_diagram_r2key_';
  static const String _prefsFile = 'pit_map_diagram_file_';

  final PhotoService photoService;
  final MapDiagramSyncService diagramSync;

  @override
  bool get isSupported => !kIsWeb;

  @override
  Future<MapDiagram?> diagramFor(MapType mapType) async {
    if (!isSupported) return null;
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
      final file = await _cachedFile(mapType);
      if (file != null) return await _diagramFromFile(file);
    }
    try {
      final bytes = await photoService.fetch(key);
      if (bytes == null) return null;
      final file = await _saveToCache(mapType, key, bytes);
      if (file == null) return null;
      await prefs.setString(_prefsKey(mapType, _prefsR2Key), key);
      return await _diagramFromFile(file);
    } catch (_) {
      return _cachedDiagram(mapType);
    }
  }

  Future<MapDiagram?> _cachedDiagram(MapType mapType) async {
    final file = await _cachedFile(mapType);
    if (file == null) return null;
    return await _diagramFromFile(file);
  }

  @override
  Future<MapDiagram?> pickDiagram(MapType mapType) async {
    if (!isSupported) return null;
    final picked = await photoService.pickImage();
    if (picked == null) return null;
    final bytes = picked.bytes;
    final key = await photoService.upload(picked);

    await diagramSync.writeKey(mapType, key);
    final prefs = await SharedPreferences.getInstance();
    final file = await _saveToCache(mapType, key, bytes);
    if (file == null) return null;
    await prefs.setString(_prefsKey(mapType, _prefsR2Key), key);
    return await _diagramFromFile(file);
  }

  @override
  Future<void> clearDiagram(MapType mapType) async {
    if (!isSupported) return;

    String? key;
    try {
      key = await diagramSync.readKey(mapType);
    } catch (_) {}
    key ??= (await SharedPreferences.getInstance()).getString(
      _prefsKey(mapType, _prefsR2Key),
    );
    if (key != null && key.isNotEmpty) {
      await photoService.delete(key);
    }
    await diagramSync.clearKey(mapType);
    final prefs = await SharedPreferences.getInstance();
    final file = await _cachedFile(mapType);
    if (file != null) {
      try {
        await file.delete();
      } catch (_) {}
    }
    await prefs.remove(_prefsKey(mapType, _prefsR2Key));
    await prefs.remove(_prefsKey(mapType, _prefsFile));
  }

  Future<File?> _cachedFile(MapType mapType) async {
    final prefs = await SharedPreferences.getInstance();
    final filename = prefs.getString(_prefsKey(mapType, _prefsFile));
    if (filename == null || filename.isEmpty) return null;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$filename');
    if (!file.existsSync()) return null;
    return file;
  }

  Future<File?> _saveToCache(
    MapType mapType,
    String key,
    Uint8List bytes,
  ) async {
    final ext = _extensionFromKey(key);
    final filename = 'diagram_${mapType.name}_$key.$ext';
    final dir = await getApplicationSupportDirectory();
    final prefs = await SharedPreferences.getInstance();
    final oldName = prefs.getString(_prefsKey(mapType, _prefsFile));
    if (oldName != null && oldName.isNotEmpty && oldName != filename) {
      final stale = File('${dir.path}/$oldName');
      if (stale.existsSync()) {
        try {
          await stale.delete();
        } catch (_) {}
      }
    }
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await prefs.setString(_prefsKey(mapType, _prefsFile), filename);
    return file;
  }

  Future<MapDiagram?> _diagramFromFile(File file) async {
    try {
      final size = await _decodeSize(file);
      return MapDiagram(image: FileImage(file), size: size);
    } catch (_) {
      return null;
    }
  }

  static Future<Size> _decodeSize(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  }

  String _prefsKey(MapType mapType, String prefix) => '$prefix${mapType.name}';

  static String _extensionFromKey(String key) {
    final dot = key.lastIndexOf('.');
    return dot < 0 ? 'png' : key.substring(dot + 1);
  }
}
