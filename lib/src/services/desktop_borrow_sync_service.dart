import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_polling.dart';
import 'in_flight_local_writes.dart';

import '../models/borrow_record.dart';
import 'borrow_sync_service.dart';

class DesktopBorrowSyncService implements BorrowSyncService {
  DesktopBorrowSyncService({
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    this._onPollError,
  });

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

  final InFlightLocalWrites<BorrowRecord> _inFlightWrites =
      InFlightLocalWrites<BorrowRecord>();

  @override
  Future<List<BorrowRecord>> fetchAll() async {
    final docs = await _firestore.listDocuments('borrowRecords');
    return docs.map((d) => BorrowRecord.fromJson(d.id, d.fields)).toList();
  }

  @override
  Future<void> upsert(BorrowRecord record) async {
    final token = _inFlightWrites.beginPush(record.id, record);
    try {
      await _firestore.setDocument('borrowRecords/${record.id}', {
        ...record.toJson(),
        'updatedAtTs': record.updatedAt.toUtc(),
      });

      _inFlightWrites.recordPush(record.id, record, token);
    } finally {
      _inFlightWrites.endWrite(record.id, token);
    }
  }

  @override
  Future<void> delete(String id) async {
    final token = _inFlightWrites.beginDelete(id);
    try {
      await _firestore.deleteDocument('borrowRecords/$id');

      _inFlightWrites.recordDelete(id, token);
    } finally {
      _inFlightWrites.endWrite(id, token);
    }
  }

  @override
  Stream<List<BorrowRecord>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (true) {
      List<BorrowRecord>? items;

      final window = _inFlightWrites.beginFetch();
      try {
        final docs = await _firestore.listDocuments('borrowRecords');
        final fetched = <String, BorrowRecord>{
          for (final d in docs) d.id: BorrowRecord.fromJson(d.id, d.fields),
        };
        items = _inFlightWrites.resolve(window, fetched).values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        _inFlightWrites.abandonFetch(window);
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
