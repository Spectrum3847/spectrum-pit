import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;
import 'desktop_polling.dart';

import '../models/borrow_record.dart';
import 'borrow_sync_service.dart';

class DesktopBorrowSyncService implements BorrowSyncService {
  DesktopBorrowSyncService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
    void Function(Object error)? onPollError,
  }) : _firestore = firestore,
       _pollInterval = pollInterval,
       _onPollError = onPollError;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

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
    var consecutiveFailures = 0;
    while (true) {
      List<BorrowRecord>? items;
      try {
        final docs = await _firestore.listDocuments('borrowRecords');
        items = docs.map((d) => BorrowRecord.fromJson(d.id, d.fields)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        consecutiveFailures++;
        try {
          _onPollError?.call(error);
        } catch (_) {}
        debugPrint('borrowRecords poll failed: $error');
      }
      if (items != null) {
        consecutiveFailures = 0;
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
      await Future<void>.delayed(
        pollDelayFor(_pollInterval, consecutiveFailures),
      );
    }
  }
}
