import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'desktop_polling.dart';
import 'in_flight_local_writes.dart';

import '../models/packing_record.dart';
import 'packing_sync_service.dart';

class DesktopPackingSyncService implements PackingSyncService {
  DesktopPackingSyncService({
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    this._onPollError,
  });

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final void Function(Object error)? _onPollError;

  final InFlightLocalWrites<PackingRecord> _inFlightWrites =
      InFlightLocalWrites<PackingRecord>();

  @override
  Future<List<PackingRecord>> fetchAll() async {
    try {
      final docs = await _firestore.listDocuments('packingRecords');
      return docs.map((d) => PackingRecord.fromJson(d.id, d.fields)).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
    } catch (error) {
      debugPrint('packingRecords fetch failed: $error');
      return const <PackingRecord>[];
    }
  }

  @override
  Future<void> upsert(PackingRecord record) async {
    final token = _inFlightWrites.beginPush(record.id, record);
    try {
      await _firestore.setDocument('packingRecords/${record.id}', {
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
      await _firestore.deleteDocument('packingRecords/$id');

      _inFlightWrites.recordDelete(id, token);
    } finally {
      _inFlightWrites.endWrite(id, token);
    }
  }

  @override
  Stream<List<PackingRecord>> streamAll() async* {
    String? last;
    var consecutiveFailures = 0;
    while (true) {
      List<PackingRecord>? items;

      final window = _inFlightWrites.beginFetch();
      try {
        final docs = await _firestore.listDocuments('packingRecords');
        final fetched = <String, PackingRecord>{
          for (final d in docs) d.id: PackingRecord.fromJson(d.id, d.fields),
        };
        items = _inFlightWrites.resolve(window, fetched).values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
      } catch (error) {
        _inFlightWrites.abandonFetch(window);
        consecutiveFailures++;
        try {
          _onPollError?.call(error);
        } catch (_) {}
        debugPrint('packingRecords poll failed: $error');
      }
      if (items != null) {
        consecutiveFailures = 0;
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
      await Future<void>.delayed(
        pollDelayFor(_pollInterval, consecutiveFailures),
      );
    }
  }
}
