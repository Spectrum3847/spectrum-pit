import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumpit/src/services/desktop_map_location_sync_service.dart';

fc.Firestore _firestore(MockClient client) => fc.Firestore(
  projectId: 'demo',
  idTokenProvider: () async => 'tok',
  httpClient: client,
);

String _doc(String collection, String id, Map<String, dynamic> fields) =>
    jsonEncode({
      'name': 'projects/demo/databases/(default)/documents/$collection/$id',
      'fields': fc.FirestoreValueCodec.encodeFields(fields),
    });

Map<String, dynamic> _locFields({
  String name = 'Pin',
  String mapType = 'lab',
}) => {
  'name': name,
  'mapType': mapType,
  'x': 0.5,
  'y': 0.5,
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

void main() {
  group('DesktopMapLocationSyncService', () {
    test('a failure on the very first poll does not end the stream', () async {
      var calls = 0;
      final service = DesktopMapLocationSyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return http.Response('offline', 503);
            }
            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('mapLocations', 'a', _locFields())),
                ],
              }),
              200,
            );
          }),
        ),
      );

      final items = await service.streamAll().first;

      expect(items.map((i) => i.id), ['a']);
      expect(calls, greaterThanOrEqualTo(2));
    });
  });
}
