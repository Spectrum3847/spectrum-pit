import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/services/lru_byte_cache.dart';

void main() {
  ByteRecordMeta record(String key, int size, int lastRead) =>
      ByteRecordMeta(key: key, sizeBytes: size, lastReadMillis: lastRead);

  test('nothing is evicted when under the limit', () {
    final evict = keysToEvict([record('a', 100, 1), record('b', 100, 2)], 1000);

    expect(evict, isEmpty);
  });

  test('evicts the least recently read first', () {
    final evict = keysToEvict([
      record('old', 400, 1),
      record('newer', 400, 2),
      record('pushes-over', 400, 3),
    ], 1000);

    expect(evict, ['old']);
  });

  test('evicts as many as it takes to get under the limit', () {
    final evict = keysToEvict([
      record('a', 400, 1),
      record('b', 400, 2),
      record('c', 400, 3),
    ], 500);

    expect(evict, ['a', 'b']);
  });

  test('a write counts as a read: touching a key protects it', () {
    final evict = keysToEvict([
      record('old', 400, 100),
      record('newer', 400, 1),
    ], 500);

    expect(evict, ['newer']);
  });

  test('an empty store evicts nothing', () {
    expect(keysToEvict(const [], 1000), isEmpty);
  });
}
