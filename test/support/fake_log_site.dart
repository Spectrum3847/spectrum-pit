import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeLogSite {
  FakeLogSite({this.partSize = 4, this.duplicateNames = const {}});

  final int partSize;
  final Set<String> duplicateNames;
  final calls = <String>[];
  final parts = <int, List<int>>{};
  final completed = <String, Map<String, dynamic>>{};
  final indexes = <String, Object?>{};
  int failPartTimes = 0;
  int status = 200;
  String? key;

  Future<void> Function(String name)? beforeUpload;

  late final client = MockClient(_handle);
  var _next = 0;
  final _names = <String, String>{};

  Future<http.Response> _handle(http.Request req) async {
    final path = req.url.path.replaceFirst('/api/', '');
    calls.add('${req.method} $path');
    key = req.headers['x-upload-key'];
    if (status != 200) return http.Response('{"error":"nope"}', status);
    if (path == 'auth') return http.Response('{"ok":true}', 200);
    if (path == 'uploads' && req.method == 'POST') {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      await beforeUpload?.call(b['name'] as String);
      if (duplicateNames.contains(b['name'])) {
        return http.Response(
          jsonEncode({'duplicate': true, 'fileId': 'dup', 'matchId': 'm0'}),
          200,
        );
      }
      final id = 'f${_next++}';
      _names[id] = b['name'] as String;
      return http.Response(
        jsonEncode({'fileId': id, 'partSize': partSize}),
        200,
      );
    }
    final seg = path.split('/');
    if (seg[0] == 'uploads' && seg.length == 4 && seg[2] == 'part') {
      if (failPartTimes > 0) {
        failPartTimes--;
        return http.Response('{"error":"flaky"}', 500);
      }
      final n = int.parse(seg[3]);
      parts[n] = req.bodyBytes;
      return http.Response(jsonEncode({'partNumber': n, 'etag': 'e$n'}), 200);
    }
    if (seg[0] == 'files' && seg.length == 3 && seg[2] == 'index') {
      indexes[seg[1]] = jsonDecode(req.body);
      return http.Response('{"ok":true}', 200);
    }
    if (seg[0] == 'uploads' && seg.length == 3 && seg[2] == 'complete') {
      completed[_names[seg[1]]!] = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'file': {}, 'matchId': 'match-${seg[1]}'}),
        200,
      );
    }
    if (seg[0] == 'uploads' && req.method == 'DELETE') {
      return http.Response('{"ok":true}', 200);
    }
    return http.Response('{"error":"no route"}', 404);
  }
}
