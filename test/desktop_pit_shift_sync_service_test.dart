import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/services/desktop_pit_shift_sync_service.dart';

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

Map<String, dynamic> _shiftFields({
  String label = 'Quals pit duty',
  String kind = 'pitDuty',
  List<String> assignedUids = const ['uid-1'],
  List<String> assignedNames = const ['Ana'],
}) => {
  'label': label,
  'kind': kind,
  'competition': 'Houston',
  'assignedUids': assignedUids,
  'assignedNames': assignedNames,
  'startMatch': 1,
  'endMatch': 20,
  'updatedAt': '2026-04-01T00:00:00.000Z',
};

void main() {
  group('DesktopPitShiftSyncService', () {
    test('fetchAll returns parsed shifts', () async {
      final service = DesktopPitShiftSyncService(
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('pitShifts', 's1', _shiftFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final shifts = await service.fetchAll();
      expect(shifts.single.id, 's1');
      expect(shifts.single.label, 'Quals pit duty');
      expect(shifts.single.kind, ShiftKind.pitDuty);
      expect(shifts.single.assignedUids, ['uid-1']);
    });

    test('upsert sends setDocument', () async {
      late Uri capturedUrl;
      late String capturedBody;
      final service = DesktopPitShiftSyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            capturedBody = request.body;
            return http.Response(_doc('pitShifts', 's2', _shiftFields()), 200);
          }),
        ),
      );
      await service.upsert(
        PitShift(
          id: 's2',
          label: 'Load out',
          kind: ShiftKind.loadOut,
          competition: 'Houston',
          assignedUids: const ['uid-2'],
          assignedNames: const ['Ben'],
          updatedAt: DateTime.utc(2026, 4, 1),
        ),
      );
      expect(capturedUrl.path, endsWith('pitShifts/s2'));
      expect(capturedBody, contains('Load out'));
      expect(capturedBody, contains('uid-2'));
    });

    test('delete sends deleteDocument', () async {
      late Uri capturedUrl;
      final service = DesktopPitShiftSyncService(
        firestore: _firestore(
          MockClient((request) async {
            capturedUrl = request.url;
            expect(request.method, 'DELETE');
            return http.Response('{}', 200);
          }),
        ),
      );
      await service.delete('s3');
      expect(capturedUrl.path, endsWith('pitShifts/s3'));
    });

    test('streamAll emits sorted shifts on first poll', () async {
      final service = DesktopPitShiftSyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('pitShifts', 'b', _shiftFields())),
                  jsonDecode(_doc('pitShifts', 'a', _shiftFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final shifts = await service.streamAll().first;
      expect(shifts.map((s) => s.id), ['a', 'b']);
    });

    test('a failure on the very first poll does not end the stream', () async {
      var calls = 0;
      final service = DesktopPitShiftSyncService(
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
                  jsonDecode(_doc('pitShifts', 'a', _shiftFields())),
                ],
              }),
              200,
            );
          }),
        ),
      );

      final shifts = await service.streamAll().first;

      expect(shifts.map((s) => s.id), ['a']);
      expect(calls, greaterThanOrEqualTo(2));
    });

    test('a reassignment alone re-emits (lists are fingerprinted)', () async {
      var calls = 0;
      final service = DesktopPitShiftSyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            final reassigned = calls > 1;
            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(
                    _doc(
                      'pitShifts',
                      'a',
                      _shiftFields(
                        assignedUids: reassigned
                            ? const ['uid-1', 'uid-2']
                            : const ['uid-1'],
                        assignedNames: reassigned
                            ? const ['Ana', 'Ben']
                            : const ['Ana'],
                      ),
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
      expect(results.first.single.assignedUids, ['uid-1']);
      expect(results.last.single.assignedUids, ['uid-1', 'uid-2']);
    });

    test('an unchanged schedule emits exactly once across polls', () async {
      final service = DesktopPitShiftSyncService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('pitShifts', 'a', _shiftFields())),
                ],
              }),
              200,
            ),
          ),
        ),
      );

      addTearDown(service.dispose);
      final emissions = <List<PitShift>>[];
      final sub = service.streamAll().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      service.dispose();
      await sub.cancel();

      expect(emissions.length, 1);
      expect(emissions.single.single.id, 'a');
    });
  });
}
