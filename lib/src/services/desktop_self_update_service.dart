import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'http_timeout_client.dart';

class DesktopSelfUpdateService {
  DesktopSelfUpdateService({
    http.Client? client,
    String? Function()? appImagePathLoader,
    Future<void> Function(String path)? makeExecutable,
    Future<void> Function(String path)? relaunch,
  }) : _client = client ?? TimeoutHttpClient(),
       _appImagePath = appImagePathLoader ?? _defaultAppImagePath,
       _makeExecutable = makeExecutable ?? _defaultMakeExecutable,
       _relaunch = relaunch ?? _defaultRelaunch;

  final http.Client _client;
  final String? Function() _appImagePath;
  final Future<void> Function(String path) _makeExecutable;
  final Future<void> Function(String path) _relaunch;

  bool get canSelfUpdate =>
      !kIsWeb && Platform.isLinux && (_appImagePath()?.isNotEmpty ?? false);

  Future<void> update(Uri url, {required String expectedSha256}) async {
    if (url.scheme != 'https') {
      throw StateError('Refusing to download a non-https update URL');
    }
    final path = _appImagePath();
    if (path == null || path.isEmpty) {
      throw StateError('Not running as an AppImage');
    }
    final request = http.Request('GET', url)..followRedirects = false;
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200 || response.bodyBytes.length < 100000) {
      throw StateError('Download failed (status ${response.statusCode})');
    }

    final actual = sha256.convert(response.bodyBytes).toString();
    final expected = expectedSha256.trim().toLowerCase();
    if (!_constantTimeHexEquals(actual, expected)) {
      throw StateError('Downloaded update failed its checksum verification');
    }

    final staged = File('$path.new');
    await staged.writeAsBytes(response.bodyBytes, flush: true);
    await _makeExecutable(staged.path);
    await staged.rename(path);
    await _relaunch(path);
  }

  static bool _constantTimeHexEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String? _defaultAppImagePath() => Platform.environment['APPIMAGE'];

  static Future<void> _defaultMakeExecutable(String path) async {
    final result = await Process.run('chmod', <String>['+x', path]);
    if (result.exitCode != 0) {
      throw StateError(
        'chmod +x failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
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
