import 'package:flutter/material.dart';

class PitPalette {
  PitPalette._();

  static const double radiusSm = 8;
  static const double radiusLg = 12;

  static const Color caseBlack = Color(0xFF131016);
  static const Color caseSurface = Color(0xFF1C1821);
  static const Color caseSurfaceStrong = Color(0xFF262130);
  static const Color outline = Color(0xFF363040);
  static const Color ink = Color(0xFFF2EFF6);
  static const Color inkMuted = Color(0xFFA9A1B5);

  static const Color lightCanvas = Color(0xFFFAF9FB);
  static const Color lightSurface = Color(0xFFF1EFF4);
  static const Color lightSurfaceStrong = Color(0xFFE7E3EE);
  static const Color lightOutline = Color(0xFFD5CFDE);
  static const Color lightInk = Color(0xFF221D28);
  static const Color lightInkMuted = Color(0xFF675F73);

  static const Color violetCore = Color(0xFF7C3AED);
  static const Color violetLifted = Color(0xFFB07CFF);
  static const Color violetDeep = Color(0xFF6D28D9);

  static const Color statusPacking = Color(0xFFF5A623);
  static const Color statusStaging = Color(0xFF38BDF8);
  static const Color statusLoading = Color(0xFF818CF8);
  static const Color statusReady = Color(0xFF34D399);
  static const Color statusOverdue = Color(0xFFF87171);

  static const Color lightStatusPacking = Color(0xFFB45309);
  static const Color lightStatusStaging = Color(0xFF0369A1);
  static const Color lightStatusLoading = Color(0xFF4F46E5);
  static const Color lightStatusReady = Color(0xFF047857);
  static const Color lightStatusOverdue = Color(0xFFB91C1C);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color canvasOf(BuildContext context) =>
      _isDark(context) ? caseBlack : lightCanvas;

  static Color surfaceOf(BuildContext context) =>
      _isDark(context) ? caseSurface : lightSurface;

  static Color surfaceStrongOf(BuildContext context) =>
      _isDark(context) ? caseSurfaceStrong : lightSurfaceStrong;

  static Color outlineOf(BuildContext context) =>
      _isDark(context) ? outline : lightOutline;

  static Color inkOf(BuildContext context) => _isDark(context) ? ink : lightInk;

  static Color inkMutedOf(BuildContext context) =>
      _isDark(context) ? inkMuted : lightInkMuted;

  static Color accentOf(BuildContext context) =>
      _isDark(context) ? violetLifted : violetDeep;
}
