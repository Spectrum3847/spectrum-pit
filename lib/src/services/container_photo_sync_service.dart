import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

const String unlabeledDocId = 'unlabeled';

String containerPhotoDocId(String location) {
  final trimmed = location.trim();
  final slug = _readableSlug(trimmed);
  return slug.isEmpty ? unlabeledDocId : '$slug-${_hash8(trimmed)}';
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
