import 'package:cloud_firestore/cloud_firestore.dart';

const String unlabeledDocId = 'unlabeled';

String containerPhotoDocId(String location) {
  final slug = location
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  return slug.isEmpty ? unlabeledDocId : slug;
}

abstract class ContainerPhotoSyncService {
  Future<String?> readKey(String location);

  Future<void> writeKey(String location, String key);

  Future<void> clearKey(String location);
}

class FirestoreContainerPhotoSyncService implements ContainerPhotoSyncService {
  FirestoreContainerPhotoSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _collection = 'containerPhotos';

  @override
  Future<String?> readKey(String location) async {
    final doc = await _firestore
        .collection(_collection)
        .doc(containerPhotoDocId(location))
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    final key = data['photoRef'];
    if (key is! String || key.isEmpty) return null;
    return key;
  }

  @override
  Future<void> writeKey(String location, String key) async {
    await _firestore
        .collection(_collection)
        .doc(containerPhotoDocId(location))
        .set({
          'location': location,
          'photoRef': key,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
  }

  @override
  Future<void> clearKey(String location) async {
    await _firestore
        .collection(_collection)
        .doc(containerPhotoDocId(location))
        .delete();
  }
}

class LocalContainerPhotoSyncService implements ContainerPhotoSyncService {
  @override
  Future<String?> readKey(String location) async => null;

  @override
  Future<void> writeKey(String location, String key) async {}

  @override
  Future<void> clearKey(String location) async {}
}
