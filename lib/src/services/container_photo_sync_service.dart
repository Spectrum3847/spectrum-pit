import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

const String unlabeledDocId = 'unlabeled';

String containerPhotoDocId(String location) {
  final trimmed = location.trim();
  final slug = _readableSlug(trimmed);
  return slug.isEmpty ? unlabeledDocId : '$slug-${_hash8(trimmed)}';
}

String legacyContainerPhotoDocId(String location) {
  final slug = _readableSlug(location.trim());
  return slug.isEmpty ? unlabeledDocId : slug;
}

List<String> containerPhotoDocIds(String location) {
  final current = containerPhotoDocId(location);
  final legacy = legacyContainerPhotoDocId(location);
  return current == legacy ? [current] : [current, legacy];
}

String _readableSlug(String location) => location
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp('^-+|-+\$'), '');

String _hash8(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 8);

abstract class ContainerPhotoSyncService {
  Future<String?> readKey(String location);

  Future<void> writeKey(String location, String key);

  Future<void> clearKey(String location);
}

const String containerPhotosCollection = 'containerPhotos';

Map<String, Object?> containerPhotoDoc(String location, String key) => {
  'location': location,
  'photoRef': key,
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
};

String? containerPhotoRefOf(Map<String, Object?>? fields) {
  final key = fields?['photoRef'];
  return key is String && key.isNotEmpty ? key : null;
}

abstract class FirestoreDocContainerPhotoSyncService
    implements ContainerPhotoSyncService {
  Future<Map<String, Object?>?> readDoc(String docId);

  Future<void> setDoc(String docId, Map<String, Object?> fields);

  Future<void> deleteDoc(String docId);

  @override
  Future<String?> readKey(String location) async {
    final ids = containerPhotoDocIds(location);
    final current = containerPhotoRefOf(await readDoc(ids.first));
    if (current != null) return current;
    for (final legacyId in ids.skip(1)) {
      final key = containerPhotoRefOf(await readDoc(legacyId));
      if (key == null) continue;
      await setDoc(ids.first, containerPhotoDoc(location, key));
      await deleteDoc(legacyId);
      return key;
    }
    return null;
  }

  @override
  Future<void> writeKey(String location, String key) =>
      setDoc(containerPhotoDocId(location), containerPhotoDoc(location, key));

  @override
  Future<void> clearKey(String location) async {
    for (final docId in containerPhotoDocIds(location)) {
      await deleteDoc(docId);
    }
  }
}

class FirestoreContainerPhotoSyncService
    extends FirestoreDocContainerPhotoSyncService {
  FirestoreContainerPhotoSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String docId) =>
      _firestore.collection(containerPhotosCollection).doc(docId);

  @override
  Future<Map<String, Object?>?> readDoc(String docId) async {
    final doc = await _doc(docId).get();
    return doc.exists ? doc.data() : null;
  }

  @override
  Future<void> setDoc(String docId, Map<String, Object?> fields) =>
      _doc(docId).set(fields);

  @override
  Future<void> deleteDoc(String docId) => _doc(docId).delete();
}

class LocalContainerPhotoSyncService implements ContainerPhotoSyncService {
  @override
  Future<String?> readKey(String location) async => null;

  @override
  Future<void> writeKey(String location, String key) async {}

  @override
  Future<void> clearKey(String location) async {}
}
