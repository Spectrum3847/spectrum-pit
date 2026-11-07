import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumpit/src/services/usage_rollup_service.dart';

DesktopUsageRollupService _service(MockClient client) =>
    DesktopUsageRollupService(
      firestore: fc.Firestore(
        projectId: 'demo',
        idTokenProvider: () async => 'tok',
        httpClient: client,
      ),
    );

void main() {
  test('reads the rollup document over REST', () async {
    final service = _service(
      MockClient((request) async {
        expect(request.url.path, endsWith('/telemetryRollup/current'));
        return http.Response(
          jsonEncode({
            'name': 'projects/demo/databases/(default)/documents/telemetryRollup/current',
            'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
              'updatedAt': '2026-08-16T06:25:00.000Z',
              'eventsCounted': 12,
              'tabs': [
                {'name': 'Packing', 'count': 7},
              ],
            }),
          }),
          200,
        );
      }),
    );

    final rollup = await service.fetch();
    expect(rollup.eventsCounted, 12);
    expect(rollup.tabs.single.name, 'Packing');
    expect(rollup.updatedAt, DateTime.utc(2026, 8, 16, 6, 25));
  });

  test('a missing document says the job has not run', () async {
    final service = _service(
      MockClient((_) async => http.Response('not found', 404)),
    );
    await expectLater(
      service.fetch(),
      throwsA(
        isA<UsageRollupUnavailable>().having(
          (e) => e.message,
          'message',
          contains('No usage rollup yet'),
        ),
      ),
    );
  });

  test('a denied read names the developer role', () async {
    final service = _service(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 403, 'status': 'PERMISSION_DENIED'},
          }),
          403,
        ),
      ),
    );
    await expectLater(
      service.fetch(),
      throwsA(
        isA<UsageRollupUnavailable>().having(
          (e) => e.message,
          'message',
          contains('developer role'),
        ),
      ),
    );
  });

  test('other API errors show the server message', () async {
    final service = _service(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 401,
              'status': 'UNAUTHENTICATED',
              'message': 'Token expired',
            },
          }),
          401,
        ),
      ),
    );
    await expectLater(
      service.fetch(),
      throwsA(
        isA<UsageRollupUnavailable>().having(
          (e) => e.message,
          'message',
          'Could not read usage data: Token expired',
        ),
      ),
    );
  });
}
