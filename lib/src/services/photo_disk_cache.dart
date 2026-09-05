import 'dart:io';

import 'package:flutter/foundation.dart' show Uint8List, debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';

class PhotoDiskCache {
  PhotoDiskCache({
    Future<Directory> Function()? directoryLoader,
    this.maxBytes = defaultMaxBytes,
  }) : _directoryLoader = directoryLoader ?? _defaultDirectory;

  static const int defaultMaxBytes = 80 * 1024 * 1024;

  final Future<Directory> Function() _directoryLoader;

  final int maxBytes;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/photo_cache');
  }

  bool get isSupported => !kIsWeb;

  Future<Uint8List?> read(String key) async {
    if (!isSupported) return null;
    try {
      final file = await _fileFor(key);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {}
      return bytes;
    } catch (error) {
      debugPrint('PhotoDiskCache read failed for $key: $error');
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    if (!isSupported) return;
    try {
      final file = await _fileFor(key);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await _trim();
    } catch (error) {
      debugPrint('PhotoDiskCache write failed for $key: $error');
    }
  }

  Future<void> remove(String key) async {
    if (!isSupported) return;
    try {
      final file = await _fileFor(key);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('PhotoDiskCache remove failed for $key: $error');
    }
  }

  Future<void> clear() async {
    if (!isSupported) return;
    try {
      final dir = await _directoryLoader();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (error) {
      debugPrint('PhotoDiskCache clear failed: $error');
    }
  }

  Future<int> currentBytes() async {
    if (!isSupported) return 0;
    try {
      final entries = await _entries();
      return entries.fold<int>(0, (sum, e) => sum + e.size);
    } catch (_) {
      return 0;
    }
  }

  Future<File> _fileFor(String key) async {
    final dir = await _directoryLoader();

    if (key.isEmpty ||
        key.contains('/') ||
        key.contains(r'\') ||
        key.contains('..')) {
      throw ArgumentError.value(key, 'key', 'not a valid cache key');
    }
    return File('${dir.path}/$key');
  }

  Future<List<({File file, int size, DateTime modified})>> _entries() async {
    final dir = await _directoryLoader();
    if (!await dir.exists()) {
      return const <({File file, int size, DateTime modified})>[];
    }
    final result = <({File file, int size, DateTime modified})>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        result.add((file: entity, size: stat.size, modified: stat.modified));
      } catch (_) {}
    }
    return result;
  }

  Future<void> _trim() async {
    final entries = await _entries();
    var total = entries.fold<int>(0, (sum, e) => sum + e.size);
    if (total <= maxBytes) return;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {}
    }
  }
}
