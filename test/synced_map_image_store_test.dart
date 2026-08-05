import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/photo_service.dart';
import 'package:spectrumpit/src/services/synced_map_image_store.dart';

import 'support/fake_map_diagram_sync_service.dart';
import 'support/photo_test_support.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

// 1x1 transparent PNG: real bytes so MapDiagram.size's image decoder resolves
// in the flutter_test VM, with no temp file and no device.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const String _r2KeyPref = 'pit_map_diagram_r2key_';

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

  // Keep photo uploads off the network: fakePhotoService stands in for the R2
  // Worker, returning the bytes back out on fetch, and a picker that returns
  // the tiny PNG stands in for the device photo library.
  PhotoService photoServiceReturningPng() => fakePhotoService(
    picker: (_) async => PickedPhoto(bytes: _png, contentType: 'image/png'),
  );

  group('SyncedMapImageStore.diagramFor', () {
    test('readKey throwing falls back to the locally cached diagram', () async {
      // Phase 1: a successful pick seeds the local file cache so the maps tab
      // still has bytes to paint later, and records the R2 key remotely.
      final seedSync = FakeMapDiagramSyncService();
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: seedSync,
      );
      final picked = await store.pickDiagram(MapType.lab);
      expect(picked, isNotNull);
      expect(seedSync.writeCalls.single.key, 'key-0.jpg');

      // Phase 2: a later read fails (offline / auth expired). The device must
      // fall back to the cached file rather than showing nothing (#95).
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
      // The fallback came entirely from the local cache: no network request
      // was issued by the photo service.
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
      // If the remote write throws, the local SharedPreferences pointer and the
      // cache file must NOT be left claiming a key the team never received
      // (#95). This holds only when writeKey runs before _saveToCache and the
      // prefs write; under the old order (local first) the cache file would
      // already exist when writeKey threw.
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
          // At the exact moment writeKey runs, _saveToCache has not yet written
          // the file -- proving the remote write precedes the local persist.
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

    test('remote clear failure still cleans up the local cache', () async {
      // Each remote step is best-effort on its own (#161): a failed remote
      // pointer clear must not prevent the local cache and preferences from
      // being removed. The remote pointer survives (the team still sees the
      // diagram), but this device no longer claims it.
      final sync = FakeMapDiagramSyncService(
        readKeyValue: 'key-0.jpg',
        clearFailure: Exception('remote clear failed'),
      );
      final store = SyncedMapImageStore(
        photoService: photoServiceReturningPng(),
        diagramSync: sync,
      );
      await store.pickDiagram(MapType.lab);

      // Completes instead of throwing: the failure is contained to the remote
      // pointer step.
      await store.clearDiagram(MapType.lab);

      expect(await sync.readKey(MapType.lab), 'key-0.jpg');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('$_r2KeyPref${MapType.lab.name}'), isNull);
      expect(_appSupport.listSync(), isEmpty);
    });
  });
}
