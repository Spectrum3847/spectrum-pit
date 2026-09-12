import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/scout_shift_mirror.dart';

abstract class ScoutShiftMirrorSyncService {
  Stream<List<ScoutShiftMirror>> streamAll();
}

class FirestoreScoutShiftMirrorSyncService
    implements ScoutShiftMirrorSyncService {
  FirestoreScoutShiftMirrorSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('scoutShifts');

  @override
  Stream<List<ScoutShiftMirror>> streamAll() =>
      _collection.snapshots().map(_itemsFrom);

  List<ScoutShiftMirror> _itemsFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => snapshot.docs
      .map((doc) => ScoutShiftMirror.fromJson(doc.id, doc.data()))
      .toList();
}

class LocalScoutShiftMirrorSyncService implements ScoutShiftMirrorSyncService {
  @override
  Stream<List<ScoutShiftMirror>> streamAll() =>
      const Stream<List<ScoutShiftMirror>>.empty();
}
