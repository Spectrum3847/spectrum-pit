import 'dart:async';

import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/services/borrow_sync_service.dart';

class FakeBorrowSyncService implements BorrowSyncService {
  final Map<String, BorrowRecord> _items = {};
  final StreamController<List<BorrowRecord>> _controller =
      StreamController<List<BorrowRecord>>.broadcast();

  // Recorded write calls, for assertions.
  final List<BorrowRecord> upserts = [];
  final List<String> deletes = [];

  /// Push a snapshot to simulate a realtime emission (used in tests).
  void emit(List<BorrowRecord> items) => _controller.add(items);

  /// Push a stream error to simulate a failed subscription (used in tests).
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<List<BorrowRecord>> fetchAll() async => _items.values.toList();

  @override
  Future<void> upsert(BorrowRecord record) async {
    upserts.add(record);
    _items[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    deletes.add(id);
    _items.remove(id);
  }

  @override
  Stream<List<BorrowRecord>> streamAll() => _controller.stream;
}
