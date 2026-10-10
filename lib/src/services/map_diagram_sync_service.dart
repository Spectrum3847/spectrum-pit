import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/map_location.dart';

abstract class MapDiagramSyncService {
  Future<String?> readKey(MapType mapType);

  Future<void> writeKey(MapType mapType, String key);

  Future<void> clearKey(MapType mapType);
}

class FirestoreMapDiagramSyncService implements MapDiagramSyncService {
  FirestoreMapDiagramSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _collection = 'mapDiagrams';

  @override
  Future<String?> readKey(MapType mapType) async {
    final doc = await _firestore
        .collection(_collection)
        .doc(mapType.name)
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    final key = data['diagramKey'];
    if (key is! String || key.isEmpty) return null;
    return key;
  }

  @override
  Future<void> writeKey(MapType mapType, String key) async {
    await _firestore.collection(_collection).doc(mapType.name).set({
      'diagramKey': key,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),

      'updatedAtTs': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> clearKey(MapType mapType) async {
    await _firestore.collection(_collection).doc(mapType.name).delete();
  }
}

class LocalMapDiagramSyncService implements MapDiagramSyncService {
  @override
  Future<String?> readKey(MapType mapType) async => null;

  @override
  Future<void> writeKey(MapType mapType, String key) async {}

  @override
  Future<void> clearKey(MapType mapType) async {}
}
