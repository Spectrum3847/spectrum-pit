import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart' show ImageProvider, MemoryImage, Size;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_location.dart';
import 'map_diagram_blob_store.dart';
import 'map_diagram_blob_store_web.dart'
    if (dart.library.io) 'map_diagram_blob_store_io.dart'
    as blob_store;

XTypeGroup diagramTypeGroup() => const XTypeGroup(
  label: 'images',
  extensions: ['png', 'jpg', 'jpeg', 'webp'],
  uniformTypeIdentifiers: ['public.image'],
);

class MapDiagram {
  const MapDiagram({required this.image, required this.size});

  final ImageProvider image;
  final Size size;
}

abstract class MapImageStore {
  Future<MapDiagram?> diagramFor(MapType mapType);

  Future<MapDiagram?> pickDiagram(MapType mapType);

  Future<void> clearDiagram(MapType mapType);

  bool get isSupported;
}

class LocalMapImageStore implements MapImageStore {
  LocalMapImageStore({
    Future<XFile?> Function()? filePicker,
    MapDiagramBlobStore? blobStore,
  }) : _filePicker = filePicker ?? _defaultFilePicker,
       _blobs = blobStore ?? blob_store.createMapDiagramBlobStore();

  static const String _prefsPrefix = 'pit_map_image_';

  final Future<XFile?> Function() _filePicker;
  final MapDiagramBlobStore _blobs;

  @override
  bool get isSupported => true;

  @override
  Future<MapDiagram?> diagramFor(MapType mapType) async {
    final prefs = await SharedPreferences.getInstance();
    final filename = prefs.getString(_prefsKey(mapType));
    if (filename == null || filename.isEmpty) return null;
    final bytes = await _blobs.read(filename);
    if (bytes == null) return null;
    return MapDiagram(
      image: MemoryImage(bytes),
      size: await _decodeSize(bytes),
    );
  }

  @override
  Future<MapDiagram?> pickDiagram(MapType mapType) async {
    final picked = await _filePicker();
    if (picked == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final filename = 'map_${mapType.name}${_extensionOf(picked.name)}';
    final previous = prefs.getString(_prefsKey(mapType));
    final bytes = await picked.readAsBytes();

    await _blobs.write(filename, bytes);
    await prefs.setString(_prefsKey(mapType), filename);
    if (previous != null && previous.isNotEmpty && previous != filename) {
      try {
        await _blobs.delete(previous);
      } catch (_) {}
    }
    return MapDiagram(
      image: MemoryImage(bytes),
      size: await _decodeSize(bytes),
    );
  }

  @override
  Future<void> clearDiagram(MapType mapType) async {
    final prefs = await SharedPreferences.getInstance();
    final filename = prefs.getString(_prefsKey(mapType));
    if (filename == null || filename.isEmpty) return;
    await _blobs.delete(filename);
    await prefs.remove(_prefsKey(mapType));
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

  String _prefsKey(MapType mapType) => '$_prefsPrefix${mapType.name}';

  static const Set<String> _allowedExtensions = {'png', 'jpg', 'jpeg', 'webp'};

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return _allowedExtensions.contains(ext) ? '.$ext' : '.png';
  }

  static Future<XFile?> _defaultFilePicker() {
    return openFile(acceptedTypeGroups: [diagramTypeGroup()]);
  }
}
