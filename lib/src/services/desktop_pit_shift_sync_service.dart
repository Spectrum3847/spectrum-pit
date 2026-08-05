import 'dart:async';
import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;
import 'desktop_polling.dart';

import '../models/pit_shift.dart';
import 'pit_shift_sync_service.dart';

class DesktopPitShiftSyncService implements PitShiftSyncService {
  DesktopPitShiftSyncService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
    void Function(Object error)? onPollError,
  }) : _firestore = firestore,
       _pollInterval = pollInterval,
       _onPollError = onPollError;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

  bool _disposed = false;

  void dispose() => _disposed = true;

  @override
  Future<List<PitShift>> fetchAll() async {
    final docs = await _firestore.listDocuments('pitShifts');
    return docs.map((d) => PitShift.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(PitShift shift) async {
    await _firestore.setDocument('pitShifts/${shift.id}', shift.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.deleteDocument('pitShifts/$id');
  }

  @override
  Stream<List<PitShift>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (!_disposed) {
      List<PitShift>? items;
      try {
        final docs = await _firestore.listDocuments('pitShifts');
        items = docs.map((d) => PitShift.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        consecutiveFailures++;
        try {
          _onPollError?.call(error);
        } catch (_) {}
        debugPrint('pitShifts poll failed: $error');
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

  String _fingerprint(PitShift s) => jsonEncode(s.toJson());
}
