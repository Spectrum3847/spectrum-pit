import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/services/desktop_self_update_service.dart'
    show DesktopSelfUpdatePlatform;
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
    final check = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );
    expect(check.update, isNotNull);
    expect(check.update!.latestVersion, 'v1.2.0');
    expect(check.update!.currentVersion, '1.1.0');
  });

  test('reports no update when the release is the same or older', () async {
    final same = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.1.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    expect(
      (await same.checkForUpdate(channel: DesktopUpdateChannel.stable)).update,
      isNull,
    );

    final older = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.0.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    expect(
      (await older.checkForUpdate(channel: DesktopUpdateChannel.stable)).update,
      isNull,
    );
  });

  test(
    'a not-newer stable release reports up to date, not no release',
    () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.1.0'),
        currentVersionLoader: () async => '1.1.0',
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(check.update, isNull);
      expect(check.hasRelease, isTrue);
    },
  );

  test('returns no release on a non-200 response', () async {
    final service = DesktopUpdateService(
      client: _clientReturning(tag: 'v9.9.9', status: 404),
      currentVersionLoader: () async => '1.0.0',
    );
    final check = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );
    expect(check.update, isNull);
    expect(check.hasRelease, isFalse);
  });

  test(
    'returns up to date when the current version cannot be parsed',
    () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v2.0.0'),
        currentVersionLoader: () async => 'unknown',
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(check.update, isNull);
      expect(check.hasRelease, isTrue);
    },
  );

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
    final check = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );
    expect(check.update, isNotNull);
    expect(check.update!.assetUrl, 'https://example.com/app.AppImage');
  });

  group('per-platform asset matching (#423)', () {
    http.Client clientWithAssets(List<Map<String, Object>> assets) {
      return MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v2.0.0',
            'html_url': 'https://example.com/releases/v2.0.0',
            'assets': assets,
          }),
          200,
        );
      });
    }

    test('picks the Windows zip when running on Windows', () async {
      final service = DesktopUpdateService(
        client: clientWithAssets([
          {
            'name': 'SpectrumPit-macos.zip',
            'browser_download_url': 'https://example.com/macos.zip',
            'digest': 'sha256:${'b' * 64}',
          },
          {
            'name': 'SpectrumPit-windows-x64.zip',
            'browser_download_url': 'https://example.com/win.zip',
            'digest': 'sha256:${'a' * 64}',
          },
        ]),
        currentVersionLoader: () async => '1.0.0',
        platformLoader: () => DesktopSelfUpdatePlatform.windows,
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(check.update!.assetUrl, 'https://example.com/win.zip');

      expect(check.update!.expectedSha256, 'a' * 64);
    });

    test('picks the macOS zip when running on macOS', () async {
      final service = DesktopUpdateService(
        client: clientWithAssets([
          {
            'name': 'SpectrumPit-windows-x64.zip',
            'browser_download_url': 'https://example.com/win.zip',
          },
          {
            'name': 'SpectrumPit-macos.zip',
            'browser_download_url': 'https://example.com/macos.zip',
            'digest': 'sha256:${'c' * 64}',
          },
        ]),
        currentVersionLoader: () async => '1.0.0',
        platformLoader: () => DesktopSelfUpdatePlatform.macos,
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(check.update!.assetUrl, 'https://example.com/macos.zip');
      expect(check.update!.expectedSha256, 'c' * 64);
    });

    test(
      'finds no asset when the release has none for this platform',
      () async {
        final service = DesktopUpdateService(
          client: clientWithAssets([
            {
              'name': 'SpectrumPit-linux-x86_64.AppImage',
              'browser_download_url': 'https://example.com/app.AppImage',
            },
          ]),
          currentVersionLoader: () async => '1.0.0',
          platformLoader: () => DesktopSelfUpdatePlatform.windows,
        );
        final check = await service.checkForUpdate(
          channel: DesktopUpdateChannel.stable,
        );
        expect(check.update, isNotNull);
        expect(check.update!.assetUrl, isNull);
        expect(check.update!.expectedSha256, isNull);
      },
    );
  });

  group('multiple same-platform assets on the rolling release (#1331)', () {
    http.Client clientWithTwoWindowsAssets() {
      return MockClient((_) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'nightly',
            'html_url': 'https://example.com/releases/nightly',
            'assets': [
              {
                'name': 'SpectrumPit-windows-x64-11.zip',
                'browser_download_url': 'https://example.com/win-11.zip',
                'digest': 'sha256:${'1' * 64}',
                'created_at': '2026-08-27T06:10:00Z',
              },
              {
                'name': 'SpectrumPit-windows-x64-12.zip',
                'browser_download_url': 'https://example.com/win-12.zip',
                'digest': 'sha256:${'2' * 64}',
                'created_at': '2026-08-28T06:10:00Z',
              },
            ],
          }),
          200,
        );
      });
    }

    test(
      'picks the most recently created asset, not the first listed',
      () async {
        final service = DesktopUpdateService(
          client: clientWithTwoWindowsAssets(),
          currentVersionLoader: () async => '1.0.0',
          platformLoader: () => DesktopSelfUpdatePlatform.windows,
        );
        final check = await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
        );
        expect(check.update, isNotNull);
        expect(check.update!.assetUrl, 'https://example.com/win-12.zip');
        expect(check.update!.expectedSha256, '2' * 64);
      },
    );

    test('an asset with no created_at never displaces a dated one', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'nightly',
            'html_url': 'https://example.com/releases/nightly',
            'assets': [
              {
                'name': 'SpectrumPit-windows-x64-12.zip',
                'browser_download_url': 'https://example.com/win-12.zip',
                'digest': 'sha256:${'2' * 64}',
                'created_at': '2026-08-28T06:10:00Z',
              },
              {
                'name': 'SpectrumPit-windows-x64-13.zip',
                'browser_download_url': 'https://example.com/win-13.zip',
                'digest': 'sha256:${'3' * 64}',
              },
            ],
          }),
          200,
        );
      });
      final service = DesktopUpdateService(
        client: client,
        currentVersionLoader: () async => '1.0.0',
        platformLoader: () => DesktopSelfUpdatePlatform.windows,
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(check.update, isNotNull);
      expect(check.update!.assetUrl, 'https://example.com/win-12.zip');
    });
  });

  test(
    'keeps checking the fallback repository when the primary has nothing',
    () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        final segments = request.url.pathSegments;
        final repo = '${segments[1]}/${segments[2]}';
        requested.add(repo);

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

      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );

      expect(requested, ['owner/primary', 'owner/fallback']);
      expect(check.update, isNotNull);
      expect(check.update!.latestVersion, 'v2.0.0');
      expect(check.update!.repository, 'owner/fallback');
    },
  );

  test('a network failure is not silently reported as up to date', () async {
    final service = DesktopUpdateService(
      client: MockClient((request) async {
        throw const SocketException('no route to host');
      }),
      currentVersionLoader: () async => '1.1.0',
    );

    await expectLater(
      service.checkForUpdate(channel: DesktopUpdateChannel.stable),
      throwsA(isA<SocketException>()),
    );
  });

  test('a transport failure is swallowed once another answered', () async {
    final client = MockClient((request) async {
      if (request.url.path.contains('owner/primary')) {
        throw const SocketException('no route to host');
      }
      return http.Response(
        jsonEncode({
          'tag_name': 'v1.0.0',
          'html_url': 'https://example.com/releases/v1.0.0',
        }),
        200,
      );
    });
    final service = DesktopUpdateService(
      client: client,
      currentVersionLoader: () async => '1.5.0',
      repositories: const ['owner/primary', 'owner/fallback'],
    );

    final check = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );

    expect(check.update, isNull);
    expect(check.hasRelease, isTrue);
  });

  test('one unreachable repository does not hide a newer one', () async {
    final client = MockClient((request) async {
      if (request.url.path.contains('owner/primary')) {
        throw const SocketException('no route to host');
      }
      return http.Response(
        jsonEncode({
          'tag_name': 'v2.0.0',
          'html_url': 'https://example.com/releases/v2.0.0',
        }),
        200,
      );
    });
    final service = DesktopUpdateService(
      client: client,
      currentVersionLoader: () async => '1.5.0',
      repositories: const ['owner/primary', 'owner/fallback'],
    );

    final check = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );

    expect(check.update, isNotNull);
    expect(check.update!.repository, 'owner/fallback');
  });

  group('update channel (#422)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to stable when nothing is persisted', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.0.0'),
        currentVersionLoader: () async => '1.0.0',
      );
      expect(await service.currentChannel(), DesktopUpdateChannel.stable);
    });

    test(
      'setChannel persists the choice for currentChannel to read back',
      () async {
        final service = DesktopUpdateService(
          client: _clientReturning(tag: 'v1.0.0'),
          currentVersionLoader: () async => '1.0.0',
        );
        await service.setChannel(DesktopUpdateChannel.nightly);
        expect(await service.currentChannel(), DesktopUpdateChannel.nightly);

        await service.setChannel(DesktopUpdateChannel.stable);
        expect(await service.currentChannel(), DesktopUpdateChannel.stable);
      },
    );

    test(
      'checkForUpdate with no explicit channel reads the persisted one',
      () async {
        final service = DesktopUpdateService(
          client: MockClient((request) async {
            expect(
              request.url.path,
              '/repos/Spectrum3847/spectrum-pit/releases/tags/nightly',
            );
            return http.Response(
              jsonEncode({
                'tag_name': 'nightly',
                'html_url': 'https://example.com/releases/nightly',
              }),
              200,
            );
          }),
          currentVersionLoader: () async => '1.0.0',
        );
        await service.setChannel(DesktopUpdateChannel.nightly);
        final check = await service.checkForUpdate();
        expect(check.update?.latestVersion, 'nightly');
      },
    );
  });

  group('nightly channel', () {
    test(
      'reads the rolling nightly release, whose tag is not semver',
      () async {
        final service = DesktopUpdateService(
          client: MockClient((request) async {
            expect(
              request.url.path,
              '/repos/Spectrum3847/spectrum-pit/releases/tags/nightly',
            );
            return http.Response(
              jsonEncode({
                'tag_name': 'nightly',
                'html_url': 'https://example.com/releases/nightly',
                'assets': [
                  {
                    'name': 'SpectrumPit-linux-x86_64.AppImage',
                    'browser_download_url':
                        'https://example.com/nightly.AppImage',
                  },
                ],
              }),
              200,
            );
          }),
          currentVersionLoader: () async => '1.0.0',
        );
        final check = await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
        );
        expect(check.update, isNotNull);
        expect(check.update!.latestVersion, 'nightly');
        expect(check.update!.assetUrl, 'https://example.com/nightly.AppImage');
      },
    );

    test('is reported with no version gate', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'nightly'),
        currentVersionLoader: () async => '9.9.9',
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(check.update, isNotNull);
    });

    test('reports nothing while the build is younger than 4 hours', () async {
      var requested = false;
      final service = DesktopUpdateService(
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '2026-08-30T00:00:00Z',
        now: () => DateTime.utc(2026, 8, 30, 2),
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(check.update, isNull);
      expect(check.hasRelease, isTrue);
      expect(requested, isFalse);
    });

    test('reports nothing just inside the freshness window', () async {
      var requested = false;
      final service = DesktopUpdateService(
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '2026-08-30T00:00:00Z',
        now: () => DateTime.utc(2026, 8, 30, 3, 59, 59),
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(check.update, isNull);
      expect(check.hasRelease, isTrue);
      expect(requested, isFalse);
    });

    test('reports an update once the build is older than 4 hours', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'nightly'),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '2026-08-30T00:00:00Z',
        now: () => DateTime.utc(2026, 8, 30, 4, 0, 1),
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(check.update?.latestVersion, 'nightly');
    });

    test(
      'treats a future build timestamp as fresh and reports up to date',
      () async {
        var requested = false;
        final service = DesktopUpdateService(
          client: MockClient((_) async {
            requested = true;
            return http.Response('{}', 200);
          }),
          currentVersionLoader: () async => '1.0.0',
          buildTimestamp: '2026-08-31T00:00:00Z',
          now: () => DateTime.utc(2026, 8, 30),
        );
        final check = await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
        );
        expect(check.update, isNull);
        expect(check.hasRelease, isTrue);
        expect(requested, isFalse);
      },
    );

    test('an empty build timestamp is treated as stale and offered', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'nightly'),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '',
        now: () => DateTime.utc(2026, 8, 30),
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(check.update?.latestVersion, 'nightly');
    });

    test(
      'a fresh nightly is up to date regardless of ignoreVersionGate',
      () async {
        var requested = false;
        final service = DesktopUpdateService(
          client: MockClient((_) async {
            requested = true;
            return http.Response('{}', 200);
          }),
          currentVersionLoader: () async => '1.0.0',
          buildTimestamp: '2026-08-30T00:00:00Z',
          now: () => DateTime.utc(2026, 8, 30, 1),
        );
        final check = await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
          ignoreVersionGate: true,
        );
        expect(check.update, isNull);
        expect(check.hasRelease, isTrue);
        expect(requested, isFalse);
      },
    );

    test('returns no release when no nightly release exists yet', () async {
      final service = DesktopUpdateService(
        client: MockClient((_) async => http.Response('Not Found', 404)),
        currentVersionLoader: () async => '1.0.0',
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(check.update, isNull);
      expect(check.hasRelease, isFalse);
    });

    test(
      'a stale nightly with a release reports hasRelease and an update',
      () async {
        final service = DesktopUpdateService(
          client: _clientReturning(tag: 'nightly'),
          currentVersionLoader: () async => '1.0.0',
          buildTimestamp: '2026-08-30T00:00:00Z',
          now: () => DateTime.utc(2026, 8, 31, 2),
        );
        final check = await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
        );
        expect(check.hasRelease, isTrue);
        expect(check.update, isNotNull);
      },
    );
  });

  group('ignoreVersionGate (#422)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('offers the stable release even when it is not newer', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.0.0'),
        currentVersionLoader: () async => '1.5.0',
      );
      expect(
        (await service.checkForUpdate(channel: DesktopUpdateChannel.stable))
            .update,
        isNull,
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
        ignoreVersionGate: true,
      );
      expect(check.update?.latestVersion, 'v1.0.0');
    });

    test('reports up to date, not an update, when switching to a track '
        'already running its newest release', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.8.0'),
        currentVersionLoader: () async => '1.8.0',
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
        ignoreVersionGate: true,
      );
      expect(check.update, isNull);
      expect(check.hasRelease, isTrue);
    });
  });
}
