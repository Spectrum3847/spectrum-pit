import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumpit/src/services/desktop_self_update_service.dart';

void main() {
  test('update swaps the AppImage and relaunches', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
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

    await service.update(Uri.parse('https://example.com/App.AppImage'));

    expect(target.readAsBytesSync(), payload);
    expect(madeExec, target.path);
    expect(relaunched, target.path);
    dir.deleteSync(recursive: true);
  });

  test('update throws on a too-small download', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response('not found', 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(Uri.parse('https://example.com/x')),
      throwsStateError,
    );
    dir.deleteSync(recursive: true);
  });

  test('update throws when not running as an AppImage', () async {
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes([], 200)),
      appImagePathLoader: () => null,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(Uri.parse('https://example.com/x')),
      throwsStateError,
    );
  });
}
