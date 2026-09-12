import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_image_store.dart';

class FakeMapImageStore implements MapImageStore {
  final Map<MapType, MapDiagram> images = {};

  MapDiagram? nextPick;

  Object? clearFailure;

  Future<void>? clearGate;

  @override
  bool isSupported = true;

  @override
  Future<MapDiagram?> diagramFor(MapType mapType) async {
    if (!isSupported) return null;
    return images[mapType];
  }

  @override
  Future<MapDiagram?> pickDiagram(MapType mapType) async {
    if (!isSupported) return null;
    final diagram = nextPick;
    if (diagram != null) images[mapType] = diagram;
    return diagram;
  }

  @override
  Future<void> clearDiagram(MapType mapType) async {
    if (!isSupported) return;
    if (clearFailure != null) throw clearFailure!;
    final gate = clearGate;
    if (gate != null) await gate;
    images.remove(mapType);
  }
}
