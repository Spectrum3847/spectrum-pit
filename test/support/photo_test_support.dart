import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumpit/src/services/photo_disk_cache.dart';
import 'package:spectrumpit/src/services/photo_service.dart';

final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH'
  '/q842iQAAAABJRU5ErkJggg==',
);

PhotoService unavailablePhotoService() => PhotoService(
  idToken: () async => null,
  httpClient: MockClient(
    (request) async => throw StateError('no request expected: ${request.url}'),
  ),
);

PhotoService fakePhotoService({
  Map<String, Uint8List>? stored,
  List<http.BaseRequest>? requests,
  String? token = 'test-token',
  Future<PickedPhoto?> Function(PhotoSource source)? picker,
  int cacheLimit = 12,
  http.Response Function(http.Request request)? respond,
  PhotoDiskCache? diskCache,
}) {
  final bucket = stored ?? <String, Uint8List>{};
  var next = 0;
  return PhotoService(
    idToken: () async => token,
    picker: picker,
    cacheLimit: cacheLimit,
    diskCache: diskCache,
    httpClient: MockClient((request) async {
      requests?.add(request);

      if (token == null ||
          request.headers['Authorization'] != 'Bearer $token') {
        return http.Response('{"error":"Unauthorized"}', 401);
      }
      if (respond != null) return respond(request);
      final key = request.url.pathSegments.length > 1
          ? request.url.pathSegments.last
          : null;
      switch (request.method) {
        case 'POST':
          final generated = 'key-${next++}.jpg';
          bucket[generated] = request.bodyBytes;
          return http.Response(
            jsonEncode({'key': generated}),
            201,
            headers: {'content-type': 'application/json'},
          );
        case 'GET':
          final bytes = bucket[key];
          if (bytes == null) return http.Response('{"error":"Not found"}', 404);
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        case 'DELETE':
          return http.Response('', bucket.remove(key) == null ? 404 : 204);
        default:
          return http.Response('', 405);
      }
    }),
  );
}
