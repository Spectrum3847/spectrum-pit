import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/desktop_launcher_service.dart';

void main() {
  test('desktopEntry points Exec at the quoted AppImage path', () {
    final entry = DesktopLauncherService.desktopEntry('/home/u/App x.AppImage');
    expect(entry, startsWith('[Desktop Entry]'));
    expect(entry, contains('Name=Spectrum Pit'));
    expect(entry, contains('Exec="/home/u/App x.AppImage" %U'));
  });

  test('isSupported needs a non-empty AppImage path on Linux', () {
    final empty = DesktopLauncherService(appImagePathLoader: () => '');
    final set = DesktopLauncherService(
      appImagePathLoader: () => '/tmp/App.AppImage',
    );
    expect(empty.isSupported, isFalse);
    // The result depends on the host: only a real Linux host reports support.
    expect(set.isSupported, Platform.isLinux);
  });

  test('registerInLauncher writes the entry under the home dir', () async {
    final dir = Directory.systemTemp.createTempSync('launcher');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = DesktopLauncherService(
      appImagePathLoader: () => '/tmp/App.AppImage',
      appDirLoader: () => null,
      homeLoader: () => dir.path,
    );

    final path = await service.registerInLauncher();

    expect(path, endsWith('/applications/spectrumpit.desktop'));
    final entry = File(path).readAsStringSync();
    expect(entry, contains('Exec="/tmp/App.AppImage"'));
    // No AppDir means no icon to install; fall back to the theme name.
    expect(entry, contains('Icon=spectrumpit\n'));
  });

  test(
    'registerInLauncher installs the AppDir icon and references it',
    () async {
      final home = Directory.systemTemp.createTempSync('launcher-home');
      final appDir = Directory.systemTemp.createTempSync('launcher-appdir');
      addTearDown(() => home.deleteSync(recursive: true));
      addTearDown(() => appDir.deleteSync(recursive: true));
      File(
        '${appDir.path}/spectrumpit.png',
      ).writeAsBytesSync(List<int>.filled(200, 0x42));
      final service = DesktopLauncherService(
        appImagePathLoader: () => '/tmp/App.AppImage',
        appDirLoader: () => appDir.path,
        homeLoader: () => home.path,
      );

      final path = await service.registerInLauncher();

      final icon = '${home.path}/.local/share/icons/spectrumpit.png';
      expect(File(icon).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), contains('Icon=$icon\n'));
    },
  );

  test('registerInLauncher skips the placeholder stub icon', () async {
    final home = Directory.systemTemp.createTempSync('launcher-home');
    final appDir = Directory.systemTemp.createTempSync('launcher-appdir');
    addTearDown(() => home.deleteSync(recursive: true));
    addTearDown(() => appDir.deleteSync(recursive: true));
    // release-desktop.yml writes an 8-byte PNG header when no icon ships.
    File(
      '${appDir.path}/spectrumpit.png',
    ).writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final service = DesktopLauncherService(
      appImagePathLoader: () => '/tmp/App.AppImage',
      appDirLoader: () => appDir.path,
      homeLoader: () => home.path,
    );

    final path = await service.registerInLauncher();

    expect(File(path).readAsStringSync(), contains('Icon=spectrumpit\n'));
  });

  test('registerInLauncher throws without an AppImage path', () async {
    final service = DesktopLauncherService(
      appImagePathLoader: () => null,
      homeLoader: () => '/home/u',
    );

    await expectLater(service.registerInLauncher(), throwsStateError);
  });

  // #202: quoting the Exec path is not enough on its own. A path holding a $ or
  // a backtick is reinterpreted by the launcher, and a literal % is read as the
  // start of a field code.
  test('desktopEntry escapes reserved characters in the Exec path', () {
    final entry = DesktopLauncherService.desktopEntry(
      r'/home/a$b/`c`/d"e"/f\g/App.AppImage',
    );

    // Each reserved character takes two backslashes, because the entry's string
    // escaping is undone before the Exec quoting is. The embedded quotes matter
    // most: an unescaped `"` would close the Exec value early and the launcher
    // would read the rest of the path as separate arguments.
    expect(
      entry,
      contains(r'Exec="/home/a\\$b/\\`c\\`/d\\"e\\"/f\\\\g/App.AppImage" %U'),
    );
    // %U is a field code the launcher must still expand, so it stays bare.
    expect(entry, contains(' %U'));
  });

  test('desktopEntry doubles a literal percent in the Exec path', () {
    final entry = DesktopLauncherService.desktopEntry(
      '/home/u/100% Done/App.AppImage',
    );

    expect(entry, contains('Exec="/home/u/100%% Done/App.AppImage" %U'));
  });
}
