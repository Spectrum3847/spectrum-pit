class ByteRecordMeta {
  const ByteRecordMeta({
    required this.key,
    required this.sizeBytes,
    required this.lastReadMillis,
  });

  final String key;
  final int sizeBytes;
  final int lastReadMillis;
}

List<String> keysToEvict(List<ByteRecordMeta> records, int maxBytes) {
  var total = records.fold<int>(0, (sum, record) => sum + record.sizeBytes);
  if (total <= maxBytes) return const <String>[];
  final byLastRead = [...records]
    ..sort((a, b) => a.lastReadMillis.compareTo(b.lastReadMillis));
  final evict = <String>[];
  for (final record in byLastRead) {
    if (total <= maxBytes) break;
    evict.add(record.key);
    total -= record.sizeBytes;
  }
  return evict;
}
