import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/services/desktop_borrow_sync_service.dart';
import 'package:spectrumpit/src/services/desktop_inventory_sync_service.dart';
import 'package:spectrumpit/src/services/desktop_packing_sync_service.dart';

fc.Firestore _firestore(MockClient client, {String? token = 'tok'}) =>
    fc.Firestore(
      projectId: 'demo',
      idTokenProvider: () async => token,
      httpClient: client,
    );

String _doc(String collection, String id, Map<String, dynamic> fields) =>
    jsonEncode({
      'name': 'projects/demo/databases/(default)/documents/$collection/$id',
      'fields': fc.FirestoreValueCodec.encodeFields(fields),
    });

Map<String, dynamic> _invFields({
  String name = 'Drill',
  String lab = 'Shelf A',
  String pit = 'Bin 1',
  String status = 'inLab',
}) => {
  'name': name,
  'labLocation': lab,
  'pitLocation': pit,
  'status': status,
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> _packFields({
  String itemId = 'Drill',
  String status = 'packing',
}) => {
  'itemId': itemId,
  'packingStatus': status,
  'updatedAt': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> _borrowFields({
  String toolName = 'Drill',
  String teamName = 'Poofs',
  int teamNumber = 254,
  bool returned = false,
}) => {
  'toolName': toolName,
  'teamName': teamName,
  'teamNumber': teamNumber,
  'competition': 'TX States',
  'checkedOutAt': '2026-03-01T10:00:00.000Z',
  'returned': returned,
  'updatedAt': '2026-03-01T10:00:00.000Z',
};

void main() {
  group('DesktopInventorySyncService', () {
    test('fetchAll returns parsed items', () async {
      final service = DesktopInventorySyncService(
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('inventoryItems', 'a', _invFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final items = await service.fetchAll();
      expect(items.length, 1);
      expect(items.first.id, 'a');
      expect(items.first.name, 'Drill');
    });

    test('upsert sends setDocument', () async {
      late Uri capturedUrl;
      late String capturedBody;
      final service = DesktopInventorySyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            capturedBody = request.body;
            return http.Response(
              _doc(
                'inventoryItems',
                'x',
                _invFields(
                  name: 'Wrench',
                  lab: 'L1',
                  pit: 'P1',
                  status: 'inPit',
                ),
              ),
              200,
            );
          }),
        ),
      );
      await service.upsert(
        InventoryItem(
          id: 'x',
          name: 'Wrench',
          labLocation: 'L1',
          pitLocation: 'P1',
          status: InventoryStatus.inPit,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(capturedUrl.path, endsWith('inventoryItems/x'));
      expect(capturedBody, contains('Wrench'));
    });

    test('delete sends deleteDocument', () async {
      late Uri capturedUrl;
      final service = DesktopInventorySyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            expect(request.method, 'DELETE');
            return http.Response('{}', 200);
          }),
        ),
      );
      await service.delete('z');
      expect(capturedUrl.path, endsWith('inventoryItems/z'));
    });

    test('streamAll emits sorted items on first poll', () async {
      final service = DesktopInventorySyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('inventoryItems', 'b', _invFields())),
                  jsonDecode(_doc('inventoryItems', 'a', _invFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final items = await service.streamAll().first;
      expect(items.map((i) => i.id), ['a', 'b']);
    });

    test('a failure on the very first poll does not end the stream', () async {
      var calls = 0;
      final service = DesktopInventorySyncService(
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
                  jsonDecode(_doc('inventoryItems', 'a', _invFields())),
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

    test('failed poll after success keeps stream alive', () async {
      var calls = 0;
      final service = DesktopInventorySyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 2) {
              return http.Response('temporarily unavailable', 503);
            }

            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(
                    _doc(
                      'inventoryItems',
                      'a',
                      _invFields(status: calls >= 3 ? 'inPit' : 'inLab'),
                    ),
                  ),
                ],
              }),
              200,
            );
          }),
        ),
      );
      final results = await service.streamAll().take(2).toList();
      expect(results.length, 2);
      expect(calls, greaterThanOrEqualTo(3));
      expect(results.first.single.status, InventoryStatus.inLab);
      expect(results.last.single.status, InventoryStatus.inPit);
    });
  });

  group('DesktopPackingSyncService', () {
    test('fetchAll returns parsed records', () async {
      final service = DesktopPackingSyncService(
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('packingRecords', 'p1', _packFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final records = await service.fetchAll();
      expect(records.length, 1);
      expect(records.first.id, 'p1');
      expect(records.first.itemId, 'Drill');
    });

    test('upsert sends setDocument', () async {
      late Uri capturedUrl;
      final service = DesktopPackingSyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            return http.Response(
              _doc(
                'packingRecords',
                'p2',
                _packFields(itemId: 'Iron', status: 'staging'),
              ),
              200,
            );
          }),
        ),
      );
      await service.upsert(
        PackingRecord(
          id: 'p2',
          itemId: 'Iron',
          packingStatus: PackingStatus.staging,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(capturedUrl.path, endsWith('packingRecords/p2'));
    });

    test('delete sends deleteDocument', () async {
      late Uri capturedUrl;
      final service = DesktopPackingSyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            expect(request.method, 'DELETE');
            return http.Response('{}', 200);
          }),
        ),
      );
      await service.delete('p3');
      expect(capturedUrl.path, endsWith('packingRecords/p3'));
    });

    test('streamAll emits sorted records', () async {
      final service = DesktopPackingSyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('packingRecords', 'b', _packFields())),
                  jsonDecode(_doc('packingRecords', 'a', _packFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final records = await service.streamAll().first;
      expect(records.map((r) => r.id), ['a', 'b']);
    });

    test('a failure on the very first poll does not end the stream', () async {
      var calls = 0;
      final service = DesktopPackingSyncService(
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
                  jsonDecode(_doc('packingRecords', 'a', _packFields())),
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

  group('DesktopBorrowSyncService', () {
    test('fetchAll returns parsed records', () async {
      final service = DesktopBorrowSyncService(
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('borrowRecords', 'b1', _borrowFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final records = await service.fetchAll();
      expect(records.length, 1);
      expect(records.first.id, 'b1');
      expect(records.first.toolName, 'Drill');
      expect(records.first.teamNumber, 254);
    });

    test('upsert sends setDocument', () async {
      late Uri capturedUrl;
      final service = DesktopBorrowSyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            return http.Response(
              _doc(
                'borrowRecords',
                'b2',
                _borrowFields(
                  toolName: 'Soldering Iron',
                  teamName: 'Mars Rovers',
                  teamNumber: 118,
                ),
              ),
              200,
            );
          }),
        ),
      );
      await service.upsert(
        BorrowRecord(
          id: 'b2',
          toolName: 'Soldering Iron',
          teamName: 'Mars Rovers',
          teamNumber: 118,
          competition: 'Worlds',
          checkedOutAt: DateTime.utc(2026, 4, 1),
          returned: false,
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
      );
      expect(capturedUrl.path, endsWith('borrowRecords/b2'));
    });

    test('delete sends deleteDocument', () async {
      late Uri capturedUrl;
      final service = DesktopBorrowSyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            expect(request.method, 'DELETE');
            return http.Response('{}', 200);
          }),
        ),
      );
      await service.delete('b3');
      expect(capturedUrl.path, endsWith('borrowRecords/b3'));
    });

    test('streamAll emits sorted records', () async {
      final service = DesktopBorrowSyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('borrowRecords', 'b', _borrowFields())),
                  jsonDecode(_doc('borrowRecords', 'a', _borrowFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final records = await service.streamAll().first;
      expect(records.map((r) => r.id), ['a', 'b']);
    });

    test('a failure on the very first poll does not end the stream', () async {
      var calls = 0;
      final service = DesktopBorrowSyncService(
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
                  jsonDecode(_doc('borrowRecords', 'a', _borrowFields())),
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

    test('fingerprint change triggers re-emission', () async {
      var calls = 0;
      final service = DesktopBorrowSyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode({
                  'documents': [
                    jsonDecode(
                      _doc(
                        'borrowRecords',
                        'a',
                        _borrowFields(returned: false),
                      ),
                    ),
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(
                    _doc('borrowRecords', 'a', _borrowFields(returned: true)),
                  ),
                ],
              }),
              200,
            );
          }),
        ),
      );
      final results = await service.streamAll().take(2).toList();
      expect(results.first.single.returned, isFalse);
      expect(results.last.single.returned, isTrue);
    });
  });
}
