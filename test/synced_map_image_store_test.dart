import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/photo_service.dart';
import 'package:spectrumpit/src/services/synced_map_image_store.dart';

import 'support/fake_map_diagram_blob_store.dart';
import 'support/fake_map_diagram_sync_service.dart';
import 'support/photo_test_support.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

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

const String _r2KeyPref = 'pit_map_diagram_r2key_';
const String _filePref = 'pit_map_diagram_file_';

late Directory _appSupport;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _appSupport = await Directory.systemTemp.createTemp('spectrumpit_diagram');
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (
          MethodCall call,
        ) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return _appSupport.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (_appSupport.existsSync()) {
      await _appSupport.delete(recursive: true);
    }
  });

  PhotoService photoServiceReturningPng() => fakePhotoService(
    picker: (_) async => PickedPhoto(bytes: _png, contentType: 'image/png'),
  );

  group('SyncedMapImageStore.diagramFor', () {
    test('readKey throwing falls back to the locally cached diagram', () async {
      final seedSync = FakeMapDiagramSyncService();
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: seedSync,
      );
      final picked = await store.pickDiagram(MapType.lab);
      expect(picked, isNotNull);
      expect(seedSync.writeCalls.single.key, 'key-0.jpg');

      final offlineSync = FakeMapDiagramSyncService(
        readFailure: Exception('firestore read failed'),
      );
      final requests = <http.BaseRequest>[];
      final offlineStore = SyncedMapImageStore(
        photoService: fakePhotoService(requests: requests),
        diagramSync: offlineSync,
      );
      final fallback = await offlineStore.diagramFor(MapType.lab);
      expect(fallback, isNotNull, reason: 'offline read should use the cache');

      expect(requests, isEmpty);
    });

    test('readKey throwing with no cached file returns null', () async {
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: FakeMapDiagramSyncService(
          readFailure: Exception('offline'),
        ),
      );
      expect(await store.diagramFor(MapType.pit), isNull);
    });
  });

  group('SyncedMapImageStore.pickDiagram', () {
    test('persists the R2 key remotely before the local pointer', () async {
      final sync = FakeMapDiagramSyncService(
        writeFailure: Exception('remote write failed'),
      );
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: sync,
      );

      await expectLater(
        store.pickDiagram(MapType.lab),
        throwsA(isA<Exception>()),
      );

      expect(sync.writeCalls.single.key, 'key-0.jpg');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('$_r2KeyPref${MapType.lab.name}'),
        isNull,
        reason: 'local R2-key pointer must not outlive a failed remote write',
      );
      expect(
        _appSupport.listSync(),
        isEmpty,
        reason: 'no cache file should be written before the remote write',
      );
    });

    test('happy path caches the diagram and records the R2 key', () async {
      var supportDirEmptyAtWriteTime = false;
      final sync = FakeMapDiagramSyncService(
        onWriteKey: (mapType, key) async {
          supportDirEmptyAtWriteTime = _appSupport.listSync().isEmpty;
        },
      );
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: sync,
      );

      final diagram = await store.pickDiagram(MapType.lab);

      expect(diagram, isNotNull);
      expect(sync.writeCalls.single.key, 'key-0.jpg');
      expect(supportDirEmptyAtWriteTime, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('$_r2KeyPref${MapType.lab.name}'), 'key-0.jpg');
      expect(_appSupport.listSync(), isNotEmpty);
    });
  });

  group('SyncedMapImageStore blob write ordering', () {
    test(
      'a failed write leaves the previous blob and pointers unchanged',
      () async {
        final blobs = FakeMapDiagramBlobStore();
        final store = SyncedMapImageStore(
          photoService: photoServiceReturningPng(),
          diagramSync: FakeMapDiagramSyncService(),
          blobStore: blobs,
        );
        await store.pickDiagram(MapType.lab);
        const firstFilename = 'diagram_lab_key-0.jpg.jpg';
        expect(blobs.blobs[firstFilename], _png);

        blobs.writeFailure = StateError('storage full');
        await expectLater(
          store.pickDiagram(MapType.lab),
          throwsA(isA<StateError>()),
        );

        expect(blobs.blobs[firstFilename], _png);
        expect(blobs.blobs.containsKey('diagram_lab_key-1.jpg.jpg'), isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('$_filePref${MapType.lab.name}'), firstFilename);
        expect(
          prefs.getString('$_r2KeyPref${MapType.lab.name}'),
          'key-0.jpg',
          reason:
              'the R2 pointer must not advance past a cache write that '
              'never landed',
        );
      },
    );

    test(
      'diagramFor falls back to the old diagram when caching the new one fails',
      () async {
        final blobs = FakeMapDiagramBlobStore();
        final bucket = <String, Uint8List>{};
        final store = SyncedMapImageStore(
          photoService: fakePhotoService(
            stored: bucket,
            picker: (_) async =>
                PickedPhoto(bytes: _png, contentType: 'image/png'),
          ),
          diagramSync: FakeMapDiagramSyncService(),
          blobStore: blobs,
        );
        await store.pickDiagram(MapType.lab);
        expect(blobs.blobs['diagram_lab_key-0.jpg.jpg'], _png);

        bucket['key-1.jpg'] = _png;
        blobs.writeFailure = StateError('storage full');
        final followerStore = SyncedMapImageStore(
          photoService: fakePhotoService(stored: bucket),
          diagramSync: FakeMapDiagramSyncService(readKeyValue: 'key-1.jpg'),
          blobStore: blobs,
        );

        final fallback = await followerStore.diagramFor(MapType.lab);

        expect(
          fallback,
          isNotNull,
          reason:
              'a failed cache write must fall back to the old diagram, '
              'not show nothing',
        );
        expect(
          blobs.blobs['diagram_lab_key-0.jpg.jpg'],
          _png,
          reason: 'the old blob must still be there for the fallback to read',
        );
      },
    );

    test('on success the new blob is written and the old one deleted after the write', () async {
      final blobs = FakeMapDiagramBlobStore();
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: FakeMapDiagramSyncService(),
        blobStore: blobs,
      );
      await store.pickDiagram(MapType.lab);
      blobs.calls.clear();

      await store.pickDiagram(MapType.lab);

      expect(blobs.calls, [
        'write:diagram_lab_key-1.jpg.jpg',
        'delete:diagram_lab_key-0.jpg.jpg',
      ]);
    });

    test('a delete that throws while cleaning up the old blob does not fail the pick', () async {
      final blobs = ThrowingDeleteMapDiagramBlobStore();
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: FakeMapDiagramSyncService(),
        blobStore: blobs,
      );
      await store.pickDiagram(MapType.lab);

      final diagram = await store.pickDiagram(MapType.lab);

      expect(diagram, isNotNull);
    });
  });

  group('SyncedMapImageStore.clearDiagram', () {
    test('deletes the R2 object, pointer, and local cache', () async {
      final requests = <http.BaseRequest>[];
      final sync = FakeMapDiagramSyncService(readKeyValue: 'key-0.jpg');
      final store = SyncedMapImageStore(
        photoService: fakePhotoService(
          requests: requests,
          picker: (_) async =>
              PickedPhoto(bytes: _png, contentType: 'image/png'),
        ),
        diagramSync: sync,
      );
      await store.pickDiagram(MapType.lab);
      expect(_appSupport.listSync(), isNotEmpty);

      await store.clearDiagram(MapType.lab);

      expect(requests.where((r) => r.method == 'DELETE'), hasLength(1));
      expect(sync.clearCalls, [MapType.lab]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('$_r2KeyPref${MapType.lab.name}'), isNull);
      expect(_appSupport.listSync(), isEmpty);
      expect(await store.diagramFor(MapType.lab), isNull);
    });

    test('remote clear failure cleans up locally, then reports', () async {
      final sync = FakeMapDiagramSyncService(
        readKeyValue: 'key-0.jpg',
        clearFailure: Exception('remote clear failed'),
      );
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: sync,
      );
      await store.pickDiagram(MapType.lab);

      await expectLater(
        store.clearDiagram(MapType.lab),
        throwsA(isA<Exception>()),
      );

      expect(await sync.readKey(MapType.lab), 'key-0.jpg');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('$_r2KeyPref${MapType.lab.name}'), isNull);
      expect(_appSupport.listSync(), isEmpty);
    });
  });
}
