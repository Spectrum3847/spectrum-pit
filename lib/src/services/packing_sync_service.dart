import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/packing_record.dart';

abstract class PackingSyncService {
  Future<List<PackingRecord>> fetchAll();

  Future<void> upsert(PackingRecord record);

  Future<void> delete(String id);

  Stream<List<PackingRecord>> streamAll();
}

class FirestorePackingSyncService implements PackingSyncService {
  FirestorePackingSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('packingRecords');

  @override
  Future<List<PackingRecord>> fetchAll() async {
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
        debugPrint('packingRecords server fetch failed: $serverError');
        debugPrint('packingRecords cache fetch failed: $cacheError');
        return const <PackingRecord>[];
      }
    }
  }

  @override
  Future<void> upsert(PackingRecord record) =>
      _collection.doc(record.id).set(record.toJson());

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();

  @override
  Stream<List<PackingRecord>> streamAll() =>
      _collection.snapshots().map(_itemsFrom);

  List<PackingRecord> _itemsFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => snapshot.docs
      .map((doc) => PackingRecord.fromJson(doc.id, doc.data()))
      .toList();
}

class LocalPackingSyncService implements PackingSyncService {
  @override
  Future<List<PackingRecord>> fetchAll() async => const <PackingRecord>[];

  @override
  Future<void> upsert(PackingRecord record) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Stream<List<PackingRecord>> streamAll() =>
      const Stream<List<PackingRecord>>.empty();
}
