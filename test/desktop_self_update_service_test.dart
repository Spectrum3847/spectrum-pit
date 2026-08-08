import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumpit/src/services/desktop_self_update_service.dart';

void main() {
  test('update swaps the AppImage and relaunches', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final payload = List<int>.filled(200000, 66);
    var madeExec = '';
    var relaunched = '';
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes(payload, 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (p) async => madeExec = p,
      relaunch: (p) async => relaunched = p,
    );

    await service.update(
      Uri.parse('https://example.com/App.AppImage'),
      expectedSha256: sha256.convert(payload).toString(),
    );

    expect(target.readAsBytesSync(), payload);

    expect(madeExec, '${target.path}.new');
    expect(relaunched, target.path);
  });

  test('update accepts an uppercase or padded digest', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final payload = List<int>.filled(200000, 66);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes(payload, 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await service.update(
      Uri.parse('https://example.com/App.AppImage'),
      expectedSha256: '  ${sha256.convert(payload).toString().toUpperCase()}\n',
    );

    expect(target.readAsBytesSync(), payload);
  });

  test('update throws on a too-small download', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response('not found', 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/x'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
  });

  test(
    'update throws on a non-200 response and leaves the target unchanged',
    () async {
      final dir = Directory.systemTemp.createTempSync('selfupdate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = File('${dir.path}/App.AppImage')
        ..writeAsBytesSync([1, 2, 3]);
      final payload = List<int>.filled(200000, 77);
      final service = DesktopSelfUpdateService(
        client: MockClient((_) async => http.Response.bytes(payload, 500)),
        appImagePathLoader: () => target.path,
        makeExecutable: (_) async {},
        relaunch: (_) async {},
      );

      await expectLater(
        service.update(
          Uri.parse('https://example.com/x'),
          expectedSha256: '0' * 64,
        ),
        throwsStateError,
      );

      expect(target.readAsBytesSync(), [1, 2, 3]);
    },
  );

  test('update rejects a non-https URL', () async {
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes([], 200)),
      appImagePathLoader: () => '/tmp/App.AppImage',
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('http://example.com/x'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
  });

  test('update verifies a supplied checksum and aborts on mismatch', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')
      ..writeAsBytesSync([1, 2, 3]);
    final payload = List<int>.filled(200000, 88);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes(payload, 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/App.AppImage'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
    expect(target.readAsBytesSync(), [1, 2, 3]);
  });

  test('update throws when not running as an AppImage', () async {
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes([], 200)),
      appImagePathLoader: () => null,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/x'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
  });

  test(
    'update rejects a redirect response without touching the target',
    () async {
      final dir = Directory.systemTemp.createTempSync('selfupdate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = File('${dir.path}/App.AppImage')
        ..writeAsBytesSync([1, 2, 3]);
      final service = DesktopSelfUpdateService(
        client: MockClient(
          (_) async => http.Response(
            'moved',
            302,
            headers: {'location': 'http://insecure.example.com/App.AppImage'},
          ),
        ),
        appImagePathLoader: () => target.path,
        makeExecutable: (_) async {},
        relaunch: (_) async {},
      );

      await expectLater(
        service.update(
          Uri.parse('https://example.com/App.AppImage'),
          expectedSha256: '0' * 64,
        ),
        throwsStateError,
      );
      expect(target.readAsBytesSync(), [1, 2, 3]);
    },
  );
}
