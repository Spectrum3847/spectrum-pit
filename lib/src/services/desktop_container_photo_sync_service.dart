import 'package:firestore_client/firestore_client.dart' as fc;

import 'container_photo_sync_service.dart';

class DesktopContainerPhotoSyncService implements ContainerPhotoSyncService {
  DesktopContainerPhotoSyncService({required fc.Firestore firestore})
    : _firestore = firestore;

  final fc.Firestore _firestore;

  static const String _collection = 'containerPhotos';

  @override
  Future<String?> readKey(String location) async {
    final doc = await _firestore.getDocument(
      '$_collection/${containerPhotoDocId(location)}',
    );
    if (doc == null) return null;
    final key = doc.fields['photoRef'];
    if (key is! String || key.isEmpty) return null;
    return key;
  }

  @override
  Future<void> writeKey(String location, String key) async {
    await _firestore
        .setDocument('$_collection/${containerPhotoDocId(location)}', {
          'location': location,
          'photoRef': key,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
  }

  @override
  Future<void> clearKey(String location) async {
    await _firestore.deleteDocument(
      '$_collection/${containerPhotoDocId(location)}',
    );
  }
}
