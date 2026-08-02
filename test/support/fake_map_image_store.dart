import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_image_store.dart';

/// Fakes diagram picking for widget tests: no real file dialog, no real
/// image decoding. Seed [images] before pumping to simulate an already-set
/// diagram; set [nextPick] to control what a "choose diagram" tap returns.
class FakeMapImageStore implements MapImageStore {
  final Map<MapType, MapDiagram> images = {};

  MapDiagram? nextPick;

  /// Set to throw from [clearDiagram] to simulate a failed remote removal.
  Object? clearFailure;

  /// When set, [clearDiagram] awaits it before resolving, so tests can hold a
  /// removal in flight and assert on the UI while it is pending.
  Future<void>? clearGate;

  @override
  bool isSupported = true;

  @override
  Future<MapDiagram?> diagramFor(MapType mapType) async => images[mapType];

  @override
  Future<MapDiagram?> pickDiagram(MapType mapType) async {
    final diagram = nextPick;
    if (diagram != null) images[mapType] = diagram;
    return diagram;
  }

  @override
  Future<void> clearDiagram(MapType mapType) async {
    if (clearFailure != null) throw clearFailure!;
    final gate = clearGate;
    if (gate != null) await gate;
    images.remove(mapType);
  }
}
