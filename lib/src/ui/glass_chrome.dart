import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:liquid_glass/liquid_glass.dart' show liquidGlassSupported;

bool get _isMacosPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

const bool spectrumGlassMacosEnabled = bool.fromEnvironment(
  'SPECTRUM_GLASS_MACOS',
);

Future<bool> spectrumGlassSupported() async {
  if (_isMacosPlatform && !spectrumGlassMacosEnabled) return false;
  return liquidGlassSupported();
}

const String glassChromeSurfaces = 'menus, sheets and dialogs';

class GlassChrome extends InheritedWidget {
  const GlassChrome({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool isEnabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassChrome>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(GlassChrome oldWidget) =>
      enabled != oldWidget.enabled;
}
