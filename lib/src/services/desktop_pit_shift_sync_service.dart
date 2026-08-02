import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/pit_shift.dart';
import 'pit_shift_sync_service.dart';

class DesktopPitShiftSyncService implements PitShiftSyncService {
  DesktopPitShiftSyncService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _firestore = firestore,
       _pollInterval = pollInterval;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

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
    while (true) {
      List<PitShift>? items;
      try {
        final docs = await _firestore.listDocuments('pitShifts');
        items = docs.map((d) => PitShift.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (_) {}
      if (items != null) {
        final fingerprint = items.map(_fingerprint).join('|');
        if (fingerprint != last) {
          last = fingerprint;
          yield items;
        }
      }
      await Future<void>.delayed(_pollInterval);
    }
  }

  String _fingerprint(PitShift s) =>
      '${s.id}:${s.label}:${s.kind.name}:${s.competition}:'
      '${s.assignedUids.join(",")}:${s.assignedNames.join(",")}:'
      '${s.startMatch ?? ''}:${s.endMatch ?? ''}:'
      '${s.startsAt?.toIso8601String() ?? ''}:'
      '${s.endsAt?.toIso8601String() ?? ''}:'
      '${s.notes ?? ''}:${s.updatedAt.toIso8601String()}';
}
