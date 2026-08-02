import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/packing_record.dart';
import 'packing_sync_service.dart';

class DesktopPackingSyncService implements PackingSyncService {
  DesktopPackingSyncService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _firestore = firestore,
       _pollInterval = pollInterval;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  @override
  Future<List<PackingRecord>> fetchAll() async {
    final docs = await _firestore.listDocuments('packingRecords');
    return docs.map((d) => PackingRecord.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(PackingRecord record) async {
    await _firestore.setDocument(
      'packingRecords/${record.id}',
      record.toJson(),
    );
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.deleteDocument('packingRecords/$id');
  }

  @override
  Stream<List<PackingRecord>> streamAll() async* {
    String? last;
    while (true) {
      List<PackingRecord>? items;
      try {
        final docs = await _firestore.listDocuments('packingRecords');
        items = docs.map((d) => PackingRecord.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (_) {}
      if (items != null) {
        final fingerprint = items
            .map(
              (i) =>
                  '${i.id}:${i.itemId}:${i.packingStatus.name}:'
                  '${i.photoRef ?? ''}:${i.updatedAt.toIso8601String()}',
            )
            .join('|');
        if (fingerprint != last) {
          last = fingerprint;
          yield items;
        }
      }
      await Future<void>.delayed(_pollInterval);
    }
  }
}
