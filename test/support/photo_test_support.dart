import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumpit/src/services/photo_service.dart';

/// A 1x1 PNG: small enough to inline, real enough for `Image.memory` to decode
/// in a widget test.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH'
  '/q842iQAAAABJRU5ErkJggg==',
);

/// A service with no ID token, so every photo read degrades to "unavailable"
/// and nothing reaches the network. The default for tests that are not about
/// photos.
PhotoService unavailablePhotoService() => PhotoService(
  idToken: () async => null,
  httpClient: MockClient(
    (request) async => throw StateError('no request expected: ${request.url}'),
  ),
);

/// A service backed by an in-memory stand-in for the Worker.
///
/// [requests] records every request that reached it, which is how the cache
/// tests tell a cache hit from a refetch.
PhotoService fakePhotoService({
  Map<String, Uint8List>? stored,
  List<http.BaseRequest>? requests,
  String? token = 'test-token',
  Future<PickedPhoto?> Function(PhotoSource source)? picker,
  int cacheLimit = 12,
  http.Response Function(http.Request request)? respond,
}) {
  final bucket = stored ?? <String, Uint8List>{};
  var next = 0;
  return PhotoService(
    idToken: () async => token,
    picker: picker,
    cacheLimit: cacheLimit,
    httpClient: MockClient((request) async {
      requests?.add(request);
      // The Worker authenticates every request with the caller's Bearer token;
      // simulate that gate so an unauthenticated request cannot hit the
      // storage logic.
      // A request with no Authorization header is rejected even when the fake
      // has no token: the Worker gates on the header being present and valid,
      // so accepting a missing one let an unauthenticated call reach the
      // storage logic in a test and pass (#184).
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
