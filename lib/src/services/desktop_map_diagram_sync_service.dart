import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/map_location.dart';
import 'map_diagram_sync_service.dart';

class DesktopMapDiagramSyncService implements MapDiagramSyncService {
  DesktopMapDiagramSyncService({required fc.Firestore firestore})
    : _firestore = firestore;

  final fc.Firestore _firestore;

  static const String _collection = 'mapDiagrams';

  @override
  Future<String?> readKey(MapType mapType) async {
    final doc = await _firestore.getDocument('$_collection/${mapType.name}');
    if (doc == null) return null;
    final key = doc.fields['diagramKey'];
    if (key is! String || key.isEmpty) return null;
    return key;
  }

  @override
  Future<void> writeKey(MapType mapType, String key) async {
    await _firestore.setDocument('$_collection/${mapType.name}', {
      'diagramKey': key,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> clearKey(MapType mapType) async {
    await _firestore.deleteDocument('$_collection/${mapType.name}');
  }
}
