import 'dart:typed_data';

abstract class PhotoDiskCache {
  static const int defaultMaxBytes = 80 * 1024 * 1024;

  bool get isSupported;

  Future<Uint8List?> read(String key);

  Future<void> write(String key, Uint8List bytes);

  Future<void> remove(String key);

  Future<void> clear();

  Future<int> currentBytes();
}
