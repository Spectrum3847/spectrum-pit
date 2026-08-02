import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/borrow_record.dart';

abstract class BorrowSyncService {
  Future<List<BorrowRecord>> fetchAll();

  Future<void> upsert(BorrowRecord record);

  Future<void> delete(String id);

  Stream<List<BorrowRecord>> streamAll();
}

class FirestoreBorrowSyncService implements BorrowSyncService {
  FirestoreBorrowSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('borrowRecords');

  @override
  Future<List<BorrowRecord>> fetchAll() async {
    try {
      final snapshot = await _collection.get();
      return _itemsFrom(snapshot);
    } catch (serverError) {
      try {
        final cached = await _collection.get(
          const GetOptions(source: Source.cache),
        );
        return _itemsFrom(cached);
      } catch (cacheError) {
        debugPrint('borrowRecords server fetch failed: $serverError');
        debugPrint('borrowRecords cache fetch failed: $cacheError');
        return const <BorrowRecord>[];
      }
    }
  }

  @override
  Future<void> upsert(BorrowRecord record) =>
      _collection.doc(record.id).set(record.toJson());

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();

  @override
  Stream<List<BorrowRecord>> streamAll() =>
      _collection.snapshots().map(_itemsFrom);

  List<BorrowRecord> _itemsFrom(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs
          .map((doc) => BorrowRecord.fromJson(doc.id, doc.data()))
          .toList();
}

class LocalBorrowSyncService implements BorrowSyncService {
  @override
  Future<List<BorrowRecord>> fetchAll() async => const <BorrowRecord>[];

  @override
  Future<void> upsert(BorrowRecord record) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Stream<List<BorrowRecord>> streamAll() =>
      const Stream<List<BorrowRecord>>.empty();
}
