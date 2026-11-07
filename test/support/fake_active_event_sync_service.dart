import 'dart:async';

import 'package:spectrumpit/src/models/active_event.dart';
import 'package:spectrumpit/src/services/active_event_sync_service.dart';

class FakeActiveEventSyncService implements ActiveEventSyncService {
  final StreamController<ActiveEvent?> _controller =
      StreamController<ActiveEvent?>.broadcast();

  final List<ActiveEvent> writes = <ActiveEvent>[];

  Object? failWith;

  void emit(ActiveEvent? event) => _controller.add(event);

  @override
  Stream<ActiveEvent?> watch() => _controller.stream;

  @override
  Future<void> write(ActiveEvent event) async {
    final error = failWith;
    if (error != null) throw error;
    writes.add(event);
  }
}
