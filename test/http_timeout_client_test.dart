import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumpit/src/services/http_timeout_client.dart';

// Every outbound client is built over this wrapper so a black-holed
// connection fails instead of hanging its await forever (#524).
void main() {
  test('a normal response passes through untouched', () async {
    final client = TimeoutHttpClient(
      inner: MockClient((_) async => http.Response('ok', 200)),
      timeout: const Duration(seconds: 1),
    );
    final response = await client.get(Uri.parse('https://example.com/x'));
    expect(response.statusCode, 200);
    expect(response.body, 'ok');
  });

  test('a hung request fails with TimeoutException', () async {
    final client = TimeoutHttpClient(
      inner: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      client.get(Uri.parse('https://example.com/hang')),
      throwsA(isA<TimeoutException>()),
    );
  });
}
