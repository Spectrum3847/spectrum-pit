import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_image_store.dart';

import 'support/fake_map_diagram_blob_store.dart';

const String _prefsPrefix = 'pit_map_image_';

final Uint8List _png = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  XFile pngFile(String path) =>
      XFile.fromData(_png, path: path, mimeType: 'image/png');

  test('pickDiagram writes the blob and returns a diagram', () async {
    final blobs = FakeMapDiagramBlobStore();
    final store = LocalMapImageStore(
      filePicker: () async => pngFile('diagram.png'),
      blobStore: blobs,
    );

    final diagram = await store.pickDiagram(MapType.lab);

    expect(diagram, isNotNull);
    expect(blobs.blobs['map_lab.png'], _png);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('$_prefsPrefix${MapType.lab.name}'), 'map_lab.png');
  });

  test(
    'a failed write leaves the previous blob and pointer untouched',
    () async {
      final blobs = FakeMapDiagramBlobStore();
      final store = LocalMapImageStore(
        filePicker: () async => pngFile('diagram.png'),
        blobStore: blobs,
      );
      await store.pickDiagram(MapType.lab);
      expect(blobs.blobs['map_lab.png'], _png);

      blobs.writeFailure = StateError('storage full');
      final failingStore = LocalMapImageStore(
        filePicker: () async => pngFile('diagram.jpg'),
        blobStore: blobs,
      );

      await expectLater(
        failingStore.pickDiagram(MapType.lab),
        throwsA(isA<StateError>()),
      );

      expect(blobs.blobs['map_lab.png'], _png);
      expect(blobs.blobs.containsKey('map_lab.jpg'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('$_prefsPrefix${MapType.lab.name}'),
        'map_lab.png',
        reason: 'the pointer must still name the blob that still exists',
      );
    },
  );

  test('on success the new blob is written and the old one deleted after the write', () async {
    final blobs = FakeMapDiagramBlobStore();
    final store = LocalMapImageStore(
      filePicker: () async => pngFile('diagram.png'),
      blobStore: blobs,
    );
    await store.pickDiagram(MapType.lab);
    blobs.calls.clear();

    final secondStore = LocalMapImageStore(
      filePicker: () async => pngFile('diagram.jpg'),
      blobStore: blobs,
    );
    await secondStore.pickDiagram(MapType.lab);

    expect(blobs.calls, ['write:map_lab.jpg', 'delete:map_lab.png']);
    expect(blobs.blobs.containsKey('map_lab.png'), isFalse);
    expect(blobs.blobs['map_lab.jpg'], _png);
  });

  test('a missing blob reads as no diagram, not an error', () async {
    SharedPreferences.setMockInitialValues({
      '$_prefsPrefix${MapType.lab.name}': 'map_lab.png',
    });
    final store = LocalMapImageStore(blobStore: FakeMapDiagramBlobStore());

    expect(await store.diagramFor(MapType.lab), isNull);
  });

  test('a delete that throws while cleaning up the old blob does not fail the pick', () async {
    final blobs = ThrowingDeleteMapDiagramBlobStore();
    final firstStore = LocalMapImageStore(
      filePicker: () async => pngFile('diagram.png'),
      blobStore: blobs,
    );
    await firstStore.pickDiagram(MapType.lab);

    final secondStore = LocalMapImageStore(
      filePicker: () async => pngFile('diagram.jpg'),
      blobStore: blobs,
    );

    final diagram = await secondStore.pickDiagram(MapType.lab);

    expect(diagram, isNotNull);
    expect(blobs.blobs['map_lab.jpg'], _png);
  });
}
