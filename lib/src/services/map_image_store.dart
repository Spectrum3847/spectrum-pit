import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show FileImage, ImageProvider, Size;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_location.dart';

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
  LocalMapImageStore({Future<XFile?> Function()? filePicker})
    : _filePicker = filePicker ?? _defaultFilePicker;

  static const String _prefsPrefix = 'pit_map_image_';

  final Future<XFile?> Function() _filePicker;

  @override
  bool get isSupported => !kIsWeb;

  @override
  Future<MapDiagram?> diagramFor(MapType mapType) async {
    if (!isSupported) return null;
    final prefs = await SharedPreferences.getInstance();
    final filename = prefs.getString(_prefsKey(mapType));
    if (filename == null || filename.isEmpty) return null;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$filename');
    if (!file.existsSync()) return null;
    return MapDiagram(image: FileImage(file), size: await _decodeSize(file));
  }

  @override
  Future<MapDiagram?> pickDiagram(MapType mapType) async {
    if (!isSupported) return null;
    final picked = await _filePicker();
    if (picked == null) return null;
    final dir = await getApplicationSupportDirectory();
    final prefs = await SharedPreferences.getInstance();
    final filename = 'map_${mapType.name}${_extensionOf(picked.name)}';

    final previous = prefs.getString(_prefsKey(mapType));
    if (previous != null && previous.isNotEmpty && previous != filename) {
      final stale = File('${dir.path}/$previous');
      if (stale.existsSync()) await stale.delete();
    }
    final dest = File('${dir.path}/$filename');
    await dest.writeAsBytes(await picked.readAsBytes());
    await prefs.setString(_prefsKey(mapType), filename);
    return MapDiagram(image: FileImage(dest), size: await _decodeSize(dest));
  }

  @override
  Future<void> clearDiagram(MapType mapType) async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    final filename = prefs.getString(_prefsKey(mapType));
    if (filename == null || filename.isEmpty) return;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$filename');
    if (file.existsSync()) await file.delete();
    await prefs.remove(_prefsKey(mapType));
  }

  static Future<Size> _decodeSize(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  }

  String _prefsKey(MapType mapType) => '$_prefsPrefix${mapType.name}';

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '.png' : name.substring(dot);
  }

  static Future<XFile?> _defaultFilePicker() {
    return openFile(acceptedTypeGroups: [diagramTypeGroup()]);
  }
}
