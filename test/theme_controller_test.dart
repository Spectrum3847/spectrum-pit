import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
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

  test('defaults glass on for iOS with no saved preference', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.liquidGlass, isTrue);
    controller.dispose();
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    test('defaults glass off for $platform with no saved preference', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final controller = ThemeController();
      await controller.bootstrap();

      expect(controller.liquidGlass, isFalse);
      controller.dispose();
    });
  }

  test('a saved false preference wins over the iOS default', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({'app_liquid_glass': false});

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.liquidGlass, isFalse);
    controller.dispose();
  });

  test('a saved true preference wins over the macOS default', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({'app_liquid_glass': true});

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.liquidGlass, isTrue);
    controller.dispose();
  });

  test('liquid glass survives a relaunch', () async {
    final first = ThemeController(liquidGlassDefault: false);
    await first.bootstrap();
    await first.setLiquidGlass(true);
    first.dispose();

    final second = ThemeController(liquidGlassDefault: false);
    await second.bootstrap();

    expect(second.liquidGlass, isTrue);
    second.dispose();
  });

  test(
    'setting glass notifies once, and re-setting the same value does not',
    () async {
      final controller = ThemeController(liquidGlassDefault: false);
      await controller.bootstrap();

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setLiquidGlass(true);
      expect(notifications, 1);

      await controller.setLiquidGlass(true);
      expect(notifications, 1);

      await controller.setLiquidGlass(false);
      expect(notifications, 2);
      controller.dispose();
    },
  );
}
