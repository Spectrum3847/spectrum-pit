import 'dart:async';

import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/services/packing_sync_service.dart';

class FakePackingSyncService implements PackingSyncService {
  final Map<String, PackingRecord> _items = {};
  final StreamController<List<PackingRecord>> _controller =
      StreamController<List<PackingRecord>>.broadcast();

  // Recorded write calls, for assertions.
  final List<PackingRecord> upserts = [];
  final List<String> deletes = [];

  /// Push a snapshot to simulate a realtime emission (used in tests).
  void emit(List<PackingRecord> items) => _controller.add(items);

  /// Push a stream error to simulate a failed subscription (used in tests).
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<List<PackingRecord>> fetchAll() async => _items.values.toList();

  @override
  Future<void> upsert(PackingRecord record) async {
    upserts.add(record);
    _items[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    deletes.add(id);
    _items.remove(id);
  }

  @override
  Stream<List<PackingRecord>> streamAll() => _controller.stream;
}
