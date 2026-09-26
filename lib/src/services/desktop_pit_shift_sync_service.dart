import 'dart:async';
import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_polling.dart';
import 'in_flight_local_writes.dart';

import '../models/pit_shift.dart';
import 'pit_shift_sync_service.dart';

class DesktopPitShiftSyncService implements PitShiftSyncService {
  DesktopPitShiftSyncService({
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    this._onPollError,
  });

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

  final InFlightLocalWrites<PitShift> _inFlightWrites =
      InFlightLocalWrites<PitShift>();

  bool _disposed = false;

  void dispose() => _disposed = true;

  @override
  Future<List<PitShift>> fetchAll() async {
    final docs = await _firestore.listDocuments('pitShifts');
    return docs.map((d) => PitShift.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(PitShift shift) async {
    final token = _inFlightWrites.beginPush(shift.id, shift);
    try {
      await _firestore.setDocument('pitShifts/${shift.id}', {
        ...shift.toJson(),
        'updatedAtTs': shift.updatedAt.toUtc(),
      });

      _inFlightWrites.recordPush(shift.id, shift, token);
    } finally {
      _inFlightWrites.endWrite(shift.id, token);
    }
  }

  @override
  Future<void> delete(String id) async {
    final token = _inFlightWrites.beginDelete(id);
    try {
      await _firestore.deleteDocument('pitShifts/$id');

      _inFlightWrites.recordDelete(id, token);
    } finally {
      _inFlightWrites.endWrite(id, token);
    }
  }

  @override
  Stream<List<PitShift>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (!_disposed) {
      List<PitShift>? items;

      final window = _inFlightWrites.beginFetch();
      try {
        final docs = await _firestore.listDocuments('pitShifts');
        final fetched = <String, PitShift>{
          for (final d in docs) d.id: PitShift.fromJson(d.id, d.fields),
        };
        items = _inFlightWrites.resolve(window, fetched).values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        _inFlightWrites.abandonFetch(window);
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
