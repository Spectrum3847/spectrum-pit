import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/borrow_record.dart';
import 'borrow_sync_service.dart';

class DesktopBorrowSyncService implements BorrowSyncService {
  DesktopBorrowSyncService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _firestore = firestore,
       _pollInterval = pollInterval;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  @override
  Future<List<BorrowRecord>> fetchAll() async {
    final docs = await _firestore.listDocuments('borrowRecords');
    return docs.map((d) => BorrowRecord.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(BorrowRecord record) async {
    await _firestore.setDocument('borrowRecords/${record.id}', record.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _firestore.deleteDocument('borrowRecords/$id');
  }

  @override
  Stream<List<BorrowRecord>> streamAll() async* {
    String? last;
    while (true) {
      List<BorrowRecord>? items;
      try {
        final docs = await _firestore.listDocuments('borrowRecords');
        items = docs.map((d) => BorrowRecord.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (_) {}
      if (items != null) {
        final fingerprint = items
            .map(
              (i) =>
                  '${i.id}:${i.itemId ?? ''}:${i.toolName}:${i.teamName}:'
                  '${i.teamNumber}:${i.competition}:'
                  '${i.checkedOutAt.toIso8601String()}:'
                  '${i.estimatedReturn?.toIso8601String() ?? ''}:'
                  '${i.checkedInAt?.toIso8601String() ?? ''}:'
                  '${i.returned}:${i.updatedAt.toIso8601String()}',
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
