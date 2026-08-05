import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumpit/src/services/desktop_update_service.dart';

http.Client _clientReturning({required String tag, int status = 200}) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'tag_name': tag,
        'html_url': 'https://example.com/releases/$tag',
      }),
      status,
    );
  });
}

void main() {
  test('reports an update when the release is newer', () async {
    final service = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.2.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    final info = await service.checkForUpdate();
    expect(info, isNotNull);
    expect(info!.latestVersion, 'v1.2.0');
    expect(info.currentVersion, '1.1.0');
  });

  test('reports no update when the release is the same or older', () async {
    final same = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.1.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    expect(await same.checkForUpdate(), isNull);

    final older = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.0.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    expect(await older.checkForUpdate(), isNull);
  });

  test('returns null on a non-200 response', () async {
    final service = DesktopUpdateService(
      client: _clientReturning(tag: 'v9.9.9', status: 404),
      currentVersionLoader: () async => '1.0.0',
    );
    expect(await service.checkForUpdate(), isNull);
  });

  test('returns null when the current version cannot be parsed', () async {
    final service = DesktopUpdateService(
      client: _clientReturning(tag: 'v2.0.0'),
      currentVersionLoader: () async => 'unknown',
    );
    expect(await service.checkForUpdate(), isNull);
  });

  test('captures the AppImage asset url when present', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'tag_name': 'v2.0.0',
          'html_url': 'https://example.com/releases/v2.0.0',
          'assets': [
            {
              'name': 'SpectrumPit-windows-x64.zip',
              'browser_download_url': 'https://example.com/win.zip',
            },
            {
              'name': 'SpectrumPit-linux-x86_64.AppImage',
              'browser_download_url': 'https://example.com/app.AppImage',
            },
          ],
        }),
        200,
      );
    });
    final service = DesktopUpdateService(
      client: client,
      currentVersionLoader: () async => '1.0.0',
    );
    final info = await service.checkForUpdate();
    expect(info, isNotNull);
    expect(info!.appImageUrl, 'https://example.com/app.AppImage');
  });

  test(
    'keeps checking the fallback repository when the primary has nothing',
    () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        final segments = request.url.pathSegments;
        final repo = '${segments[1]}/${segments[2]}';
        requested.add(repo);
        // The primary has no newer release; the fallback does.
        final tag = segments[2] == 'primary' ? 'v1.0.0' : 'v2.0.0';
        return http.Response(
          jsonEncode({
            'tag_name': tag,
            'html_url': 'https://example.com/releases/$tag',
          }),
          200,
        );
      });
      final service = DesktopUpdateService(
        client: client,
        currentVersionLoader: () async => '1.5.0',
        repositories: const ['owner/primary', 'owner/fallback'],
      );

      final info = await service.checkForUpdate();

      // A null (no-newer) result from the primary does not end the search.
      expect(requested, ['owner/primary', 'owner/fallback']);
      expect(info, isNotNull);
      expect(info!.latestVersion, 'v2.0.0');
      expect(info.repository, 'owner/fallback');
    },
  );
}
