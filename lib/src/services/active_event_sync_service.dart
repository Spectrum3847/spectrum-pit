import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/active_event.dart';

abstract class ActiveEventSyncService {
  Stream<ActiveEvent?> watch();

  Future<void> write(ActiveEvent event);
}

class FirestoreActiveEventSyncService implements ActiveEventSyncService {
  FirestoreActiveEventSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('appConfig').doc('activeEvent');

  @override
  Stream<ActiveEvent?> watch() =>
      _doc.snapshots().map((snap) => ActiveEvent.fromJson(snap.data()));

  @override
  Future<void> write(ActiveEvent event) => _doc.set({
    ...event.toJson(),

    'updatedAtTs': FieldValue.serverTimestamp(),
  });
}

class LocalActiveEventSyncService implements ActiveEventSyncService {
  @override
  Stream<ActiveEvent?> watch() => const Stream<ActiveEvent?>.empty();

  @override
  Future<void> write(ActiveEvent event) async {}
}
