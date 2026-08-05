import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/pit_shift.dart';

abstract class PitShiftSyncService {
  Future<List<PitShift>> fetchAll();

  Future<void> upsert(PitShift shift);

  Future<void> delete(String id);

  Stream<List<PitShift>> streamAll();
}

class FirestorePitShiftSyncService implements PitShiftSyncService {
  FirestorePitShiftSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('pitShifts');

  @override
  Future<List<PitShift>> fetchAll() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _collection.get();
    } catch (serverError) {
      try {
        final cached = await _collection.get(
          const GetOptions(source: Source.cache),
        );
        return _itemsFrom(cached);
      } catch (cacheError) {
        debugPrint('pitShifts server fetch failed: $serverError');
        debugPrint('pitShifts cache fetch failed: $cacheError');
        return const <PitShift>[];
      }
    }
    return _itemsFrom(snapshot);
  }

  @override
  Future<void> upsert(PitShift shift) =>
      _collection.doc(shift.id).set(shift.toJson());

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();

  @override
  Stream<List<PitShift>> streamAll() => _collection.snapshots().map(_itemsFrom);

  List<PitShift> _itemsFrom(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs
          .map((doc) => PitShift.fromJson(doc.id, doc.data()))
          .toList();
}

class LocalPitShiftSyncService implements PitShiftSyncService {
  @override
  Future<List<PitShift>> fetchAll() async => const <PitShift>[];

  @override
  Future<void> upsert(PitShift shift) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Stream<List<PitShift>> streamAll() => const Stream<List<PitShift>>.empty();
}
