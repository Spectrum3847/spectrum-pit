import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/active_event.dart';
import 'active_event_sync_service.dart';
import 'desktop_polling.dart';

class DesktopActiveEventSyncService implements ActiveEventSyncService {
  DesktopActiveEventSyncService({
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
  });

  static const String _path = 'appConfig/activeEvent';

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  int _writes = 0;
  int _writesInFlight = 0;

  @override
  Stream<ActiveEvent?> watch() {
    var cancelled = false;
    late final StreamController<ActiveEvent?> controller;

    Future<void> poll() async {
      var first = true;
      ActiveEvent? last;
      var consecutiveFailures = 0;
      while (!cancelled) {
        final writesBefore = _writes;
        try {
          final doc = await _firestore.getDocument(_path);
          consecutiveFailures = 0;
          final event = ActiveEvent.fromJson(doc?.fields);
          if (!cancelled &&
              _writesInFlight == 0 &&
              writesBefore == _writes &&
              (first || event != last)) {
            first = false;
            last = event;
            controller.add(event);
          }
        } catch (error) {
          consecutiveFailures++;
          debugPrint('activeEvent poll failed: $error');
        }
        await Future<void>.delayed(
          pollDelayFor(_pollInterval, consecutiveFailures),
        );
      }
    }

    controller = StreamController<ActiveEvent?>(
      onListen: poll,
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }

  @override
  Future<void> write(ActiveEvent event) async {
    _writes++;
    _writesInFlight++;
    try {
      await _firestore.setDocument(_path, {
        ...event.toJson(),

        'updatedAtTs': event.updatedAt.toUtc(),
      });
    } finally {
      _writesInFlight--;
      _writes++;
    }
  }
}
