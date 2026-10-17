import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/ui/glass_chrome.dart';

void main() {
  group('spectrumGlassSupported', () {
    test('is off on macOS without SPECTRUM_GLASS_MACOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(await spectrumGlassSupported(), isFalse);
    });

    test('defers to the plugin off macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(await spectrumGlassSupported(), isFalse);
    });

    test('the compile-time define defaults off', () {
      expect(spectrumGlassMacosEnabled, isFalse);
    });
  });
}
