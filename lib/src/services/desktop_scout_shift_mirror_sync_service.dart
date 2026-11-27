import 'dart:async';
import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_polling.dart';

import '../models/scout_shift_mirror.dart';
import 'scout_shift_mirror_sync_service.dart';

class DesktopScoutShiftMirrorSyncService
    implements ScoutShiftMirrorSyncService {
  DesktopScoutShiftMirrorSyncService({
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    this._onPollError,
  });

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

  bool _disposed = false;

  void dispose() => _disposed = true;

  @override
  Stream<List<ScoutShiftMirror>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (!_disposed) {
      List<ScoutShiftMirror>? items;
      try {
        final docs = await _firestore.listDocuments('scoutShifts');
        items =
            docs.map((d) => ScoutShiftMirror.fromJson(d.id, d.fields)).toList()
              ..sort((a, b) => a.eventKey.compareTo(b.eventKey));
      } catch (error) {
        consecutiveFailures++;
        try {
          _onPollError?.call(error);
        } catch (_) {}
        debugPrint('scoutShifts poll failed: $error');
      }
      if (items != null) {
        consecutiveFailures = 0;
        final fingerprint = items.map(_fingerprint).join('|');
        if (fingerprint != last) {
          last = fingerprint;
          yield items;
        }
      }
      await Future<void>.delayed(
        pollDelayFor(_pollInterval, consecutiveFailures),
      );
    }
  }

  String _fingerprint(ScoutShiftMirror m) => jsonEncode(m.toJson());
}
