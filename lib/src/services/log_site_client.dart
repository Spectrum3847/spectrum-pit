import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class LogSiteClient {
  LogSiteClient({
    required String site,
    required this.key,
    http.Client? client,
    this.retryDelay = const Duration(seconds: 1),
  }) : _base = site.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String _base;
  final String key;
  final http.Client _client;
  final Duration retryDelay;

  Future<Object?> _call(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
  }) async {
    final req = http.Request(method, Uri.parse('$_base/api/$path'));
    if (key.isNotEmpty) req.headers['x-upload-key'] = key;
    if (json != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(json);
    } else if (bytes != null) {
      req.headers['content-type'] = 'application/octet-stream';
      req.bodyBytes = bytes;
    }
    final res = await http.Response.fromStream(
      await _client.send(req).timeout(const Duration(minutes: 2)),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var msg = res.body;
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['error'] is String) msg = j['error'] as String;
      } on FormatException {}
      throw LogSiteException(res.statusCode, '$method $path: $msg');
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<void> checkKey() => _call('POST', 'auth');

  Future<LogSiteUpload> upload(
    File file, {
    required String name,
    required String kind,
    required Map<String, dynamic> filing,
    Map<String, dynamic>? index,
    void Function(double)? onProgress,
  }) async {
    final size = await file.length();
    final start = await _call(
      'POST',
      'uploads',
      json: {'name': name, 'size': size, 'kind': kind},
    ) as Map<String, dynamic>;
    final fileId = start['fileId'] as String;
    if (start['duplicate'] == true) {
      return LogSiteUpload(
        fileId: fileId,
        matchId: start['matchId'] as String?,
        duplicate: true,
      );
    }
    final partSize = (start['partSize'] as num).toInt();
    final raf = await file.open();
    try {
      final parts = <Object?>[];
      final count = size == 0 ? 1 : (size + partSize - 1) ~/ partSize;
      for (var i = 0; i < count; i++) {
        await raf.setPosition(i * partSize);
        final buf = await raf.read(partSize);
        for (var attempt = 1; ; attempt++) {
          try {
            parts.add(
              await _call('PUT', 'uploads/$fileId/part/${i + 1}', bytes: buf),
            );
            break;
          } on Object catch (e) {
            if (attempt >= 4 || (e is LogSiteException && e.status == 401)) {
              rethrow;
            }
            await Future<void>.delayed(retryDelay * (1 << attempt));
          }
        }
        onProgress?.call((i + 1) / count);
      }
      if (index != null) await _call('PUT', 'files/$fileId/index', json: index);
      final done = await _call(
        'POST',
        'uploads/$fileId/complete',
        json: {...filing, 'parts': parts},
      ) as Map<String, dynamic>;
      return LogSiteUpload(
        fileId: fileId,
        matchId: done['matchId'] as String?,
        duplicate: false,
      );
    } on Object {
      await _call('DELETE', 'uploads/$fileId').catchError((_) => null);
      rethrow;
    } finally {
      await raf.close();
    }
  }
}

class LogSiteUpload {
  const LogSiteUpload({
    required this.fileId,
    required this.matchId,
    required this.duplicate,
  });
  final String fileId;
  final String? matchId;
  final bool duplicate;
}

class LogSiteException implements Exception {
  const LogSiteException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}
