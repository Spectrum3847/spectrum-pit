import 'dart:async';

import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/services/pit_shift_sync_service.dart';

class FakePitShiftSyncService implements PitShiftSyncService {
  final Map<String, PitShift> _items = {};
  final StreamController<List<PitShift>> _controller =
      StreamController<List<PitShift>>.broadcast();

  // Recorded write calls, for assertions.
  final List<PitShift> upserts = [];
  final List<String> deletes = [];

  /// Set to make the next [upsert] or [delete] call fail, simulating an
  /// offline or auth-expired sync write.
  Object? failWith;

  // Fires once: the doc above promises the NEXT write fails, so clear it as it
  // throws. Retaining it would fail every later write and make a recovery path
  // impossible to test.
  void _throwIfConfigured() {
    final failure = failWith;
    if (failure == null) return;
    failWith = null;
    throw failure;
  }

  /// Push a snapshot to simulate a realtime emission (used in tests).
  void emit(List<PitShift> items) => _controller.add(items);

  void emitError(Object error) => _controller.addError(error);

  @override
  Future<List<PitShift>> fetchAll() async => _items.values.toList();

  @override
  Future<void> upsert(PitShift shift) async {
    _throwIfConfigured();
    upserts.add(shift);
    _items[shift.id] = shift;
  }

  @override
  Future<void> delete(String id) async {
    _throwIfConfigured();
    deletes.add(id);
    _items.remove(id);
  }

  @override
  Stream<List<PitShift>> streamAll() => _controller.stream;
}
