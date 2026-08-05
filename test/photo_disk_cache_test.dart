import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/services/photo_disk_cache.dart';

// #164: photos were cached in memory only, so scrolling the packing list after a
// relaunch refetched every image over venue wifi. The disk cache keeps them
// across launches, bounded by total size and evicted least-recently-read.
void main() {
  late Directory base;
  late PhotoDiskCache cache;

  Uint8List bytes(int size, [int fill = 7]) =>
      Uint8List.fromList(List<int>.filled(size, fill));

  setUp(() async {
    base = await Directory.systemTemp.createTemp('photo_cache_test');
    cache = PhotoDiskCache(
      directoryLoader: () async => Directory('${base.path}/photos'),
      maxBytes: 1000,
    );
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('a written photo reads back', () async {
    await cache.write('abc', bytes(10, 3));

    expect(await cache.read('abc'), bytes(10, 3));
  });

  test('a miss is null, not an error', () async {
    // The cache must never fail a fetch, only save one.
    expect(await cache.read('never-stored'), isNull);
  });

  test('remove drops it', () async {
    await cache.write('abc', bytes(10));
    await cache.remove('abc');

    expect(await cache.read('abc'), isNull);
  });

  test('removing something absent is not an error', () async {
    // delete() calls this unconditionally.
    await cache.remove('never-stored');
  });

  test('clear empties everything', () async {
    await cache.write('a', bytes(10));
    await cache.write('b', bytes(10));

    await cache.clear();

    expect(await cache.read('a'), isNull);
    expect(await cache.read('b'), isNull);
    expect(await cache.currentBytes(), 0);
  });

  test('the cache is trimmed back under its limit', () async {
    // Four 300-byte photos against a 1000-byte cap: one has to go.
    await cache.write('a', bytes(300));
    await cache.write('b', bytes(300));
    await cache.write('c', bytes(300));
    await cache.write('d', bytes(300));

    expect(await cache.currentBytes(), lessThanOrEqualTo(1000));
  });

  test(
    'eviction drops the least recently read, not the oldest written',
    () async {
      await cache.write('old', bytes(400));
      await cache.write('newer', bytes(400));

      // Times set explicitly rather than by sleeping between writes: wall-clock
      // gaps made this flaky, and the eviction order is the only thing under test.
      // 'old' is the most recently read, so it must survive.
      final dir = Directory('${base.path}/photos');
      await File('${dir.path}/old').setLastModified(DateTime.now());
      await File(
        '${dir.path}/newer',
      ).setLastModified(DateTime.now().subtract(const Duration(hours: 1)));

      await cache.write('pushes-over', bytes(400));

      expect(
        await cache.read('old'),
        isNotNull,
        reason: 'it was read most recently',
      );
      expect(await cache.read('newer'), isNull, reason: 'it was the stale one');
    },
  );

  test('a key that could escape the directory reads as a miss', () async {
    // Keys come from the Worker and should be safe, but they end up in a path,
    // so the guard refuses them. read() still returns null rather than throwing:
    // the cache must never fail a fetch, only save one.
    for (final key in <String>['', '../escape', 'a/b', r'a\b', '..']) {
      expect(await cache.read(key), isNull, reason: 'key: $key');
    }
  });

  test('a key that could escape the directory writes nothing', () async {
    await cache.write('../escape', bytes(10));

    // Nothing landed anywhere, including outside the cache directory.
    expect(await cache.currentBytes(), 0);
    expect(await File('${base.path}/escape').exists(), isFalse);
  });

  test('reading from an empty cache directory reports zero bytes', () async {
    expect(await cache.currentBytes(), 0);
  });
}
