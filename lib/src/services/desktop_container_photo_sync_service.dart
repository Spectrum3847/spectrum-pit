import 'package:firestore_client/firestore_client.dart' as fc;

import 'container_photo_sync_service.dart';

class DesktopContainerPhotoSyncService
    extends FirestoreDocContainerPhotoSyncService {
  DesktopContainerPhotoSyncService({required this._firestore});

  final fc.Firestore _firestore;

  String _path(String docId) => '$containerPhotosCollection/$docId';

  @override
  Future<Map<String, Object?>?> readDoc(String docId) async {
    final doc = await _firestore.getDocument(_path(docId));
    return doc?.fields;
  }

  @override
  Future<void> setDoc(String docId, Map<String, Object?> fields) =>
      _firestore.setDocument(_path(docId), fields);

  @override
  Future<void> deleteDoc(String docId) =>
      _firestore.deleteDocument(_path(docId));
}
