import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class DesktopSelfUpdateService {
  DesktopSelfUpdateService({
    http.Client? client,
    String? Function()? appImagePathLoader,
    Future<void> Function(String path)? makeExecutable,
    Future<void> Function(String path)? relaunch,
  }) : _client = client ?? http.Client(),
       _appImagePath = appImagePathLoader ?? _defaultAppImagePath,
       _makeExecutable = makeExecutable ?? _defaultMakeExecutable,
       _relaunch = relaunch ?? _defaultRelaunch;

  final http.Client _client;
  final String? Function() _appImagePath;
  final Future<void> Function(String path) _makeExecutable;
  final Future<void> Function(String path) _relaunch;

  bool get canSelfUpdate =>
      !kIsWeb && Platform.isLinux && (_appImagePath()?.isNotEmpty ?? false);

  Future<void> update(Uri url) async {
    final path = _appImagePath();
    if (path == null || path.isEmpty) {
      throw StateError('Not running as an AppImage');
    }
    final response = await _client.get(url);

    if (response.statusCode != 200 || response.bodyBytes.length < 100000) {
      throw StateError('Download failed (status ${response.statusCode})');
    }

    final staged = File('$path.new');
    await staged.writeAsBytes(response.bodyBytes, flush: true);
    await staged.rename(path);
    await _makeExecutable(path);
    await _relaunch(path);
  }

  static String? _defaultAppImagePath() => Platform.environment['APPIMAGE'];

  static Future<void> _defaultMakeExecutable(String path) async {
    await Process.run('chmod', <String>['+x', path]);
  }

  static Future<void> _defaultRelaunch(String path) async {
    await Process.start(
      path,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
