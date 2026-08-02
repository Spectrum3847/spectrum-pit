import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/state/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts with system theme when no stored value', () async {
    final controller = ThemeController();
    await controller.bootstrap();
    expect(controller.themeMode, ThemeMode.system);
    controller.dispose();
  });

  test('restores stored theme mode', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'dark'});
    final controller = ThemeController();
    await controller.bootstrap();
    expect(controller.themeMode, ThemeMode.dark);
    controller.dispose();
  });

  test('falls back to system for unknown stored value', () async {
    SharedPreferences.setMockInitialValues({'app_theme_mode': 'neon'});
    final controller = ThemeController();
    await controller.bootstrap();
    expect(controller.themeMode, ThemeMode.system);
    controller.dispose();
  });

  test('setThemeMode persists and notifies', () async {
    final controller = ThemeController();
    await controller.bootstrap();

    var notified = false;
    controller.addListener(() => notified = true);

    await controller.setThemeMode(ThemeMode.dark);

    expect(controller.themeMode, ThemeMode.dark);
    expect(notified, isTrue);

    // A new controller reads the same mock store, proving it persisted.
    final reopened = ThemeController();
    await reopened.bootstrap();
    expect(reopened.themeMode, ThemeMode.dark);
    controller.dispose();
    reopened.dispose();
  });

  test('setThemeMode is a no-op for same value', () async {
    final controller = ThemeController();
    await controller.bootstrap();
    expect(controller.themeMode, ThemeMode.system);

    var notified = false;
    controller.addListener(() => notified = true);

    await controller.setThemeMode(ThemeMode.system);

    expect(notified, isFalse);
    controller.dispose();
  });

  test('bootstrap is idempotent', () async {
    final controller = ThemeController();
    await Future.wait([controller.bootstrap(), controller.bootstrap()]);
    expect(controller.themeMode, ThemeMode.system);
    controller.dispose();
  });
}
