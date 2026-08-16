import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/services/container_photo_sync_service.dart';

void main() {
  group('containerPhotoDocId', () {
    test('keeps a readable slug prefix', () {
      expect(containerPhotoDocId('Road Case 1'), startsWith('road-case-1-'));
    });

    test('collapses a slash so the doc id stays Firestore-safe', () {
      final id = containerPhotoDocId('Cart 1/Drawer 2');
      expect(id, startsWith('cart-1-drawer-2-'));
      expect(id, matches(RegExp(r'^[a-z0-9-]+-[0-9a-f]{8}$')));
    });

    test('lowercases mixed case for the prefix', () {
      expect(containerPhotoDocId('Road CASE 1'), startsWith('road-case-1-'));
    });

    test('trims leading and trailing whitespace', () {
      expect(containerPhotoDocId('  Cart 1  '), containerPhotoDocId('Cart 1'));
    });

    test('collapses runs of separators to one dash', () {
      expect(
        containerPhotoDocId('Cart 1 / Drawer 2'),
        startsWith('cart-1-drawer-2-'),
      );
    });

    test('falls back to the placeholder when nothing is left', () {
      expect(containerPhotoDocId(''), unlabeledDocId);
      expect(containerPhotoDocId('   '), unlabeledDocId);
      expect(containerPhotoDocId('///'), unlabeledDocId);
    });

    test('is deterministic for the same input', () {
      expect(
        containerPhotoDocId('Road Case 1'),
        containerPhotoDocId('Road Case 1'),
      );
      expect(
        containerPhotoDocId('Drawer A/B'),
        containerPhotoDocId('Drawer A/B'),
      );
    });

    test('distinct locations that share a slug do not collide', () {
      expect(
        containerPhotoDocId('Drawer A/B'),
        isNot(containerPhotoDocId('Drawer A B')),
      );
    });
  });

  group('legacy document ids', () {
    test('the legacy id is the slug the hashed id is built from', () {
      expect(legacyContainerPhotoDocId('Road Case 1'), 'road-case-1');
      expect(
        containerPhotoDocId('Road Case 1'),
        startsWith('${legacyContainerPhotoDocId('Road Case 1')}-'),
      );
    });

    test('a blank location has only the one id it has always had', () {
      expect(containerPhotoDocIds(''), [unlabeledDocId]);
      expect(containerPhotoDocIds('   '), [unlabeledDocId]);
    });

    test('a real location lists the current id first', () {
      expect(containerPhotoDocIds('Road Case 1'), [
        containerPhotoDocId('Road Case 1'),
        'road-case-1',
      ]);
    });
  });

  group('FirestoreDocContainerPhotoSyncService', () {
    test('reads the current document id', () async {
      final service = _FakeDocService({
        containerPhotoDocId('Road Case 1'): {'photoRef': 'photos/new.jpg'},
      });

      expect(await service.readKey('Road Case 1'), 'photos/new.jpg');
      expect(service.deleted, isEmpty);
    });

    test('reads a document written at the legacy id (#265)', () async {
      final service = _FakeDocService({
        'road-case-1': {'photoRef': 'photos/old.jpg'},
      });

      expect(await service.readKey('Road Case 1'), 'photos/old.jpg');
    });

    test('migrates a legacy document to the current id on read', () async {
      final service = _FakeDocService({
        'road-case-1': {'photoRef': 'photos/old.jpg'},
      });

      await service.readKey('Road Case 1');

      expect(
        service.docs[containerPhotoDocId('Road Case 1')]?['photoRef'],
        'photos/old.jpg',
      );
      expect(
        service.docs[containerPhotoDocId('Road Case 1')]?['location'],
        'Road Case 1',
      );
      expect(service.docs, isNot(contains('road-case-1')));
      expect(await service.readKey('Road Case 1'), 'photos/old.jpg');
    });

    test('prefers the current document over a stale legacy one', () async {
      final service = _FakeDocService({
        containerPhotoDocId('Road Case 1'): {'photoRef': 'photos/new.jpg'},
        'road-case-1': {'photoRef': 'photos/old.jpg'},
      });

      expect(await service.readKey('Road Case 1'), 'photos/new.jpg');
      expect(service.docs, contains('road-case-1'));
    });

    test('a location with no document anywhere reads as null', () async {
      final service = _FakeDocService({});

      expect(await service.readKey('Road Case 1'), isNull);
    });

    test('an empty photoRef is not a photo', () async {
      final service = _FakeDocService({
        containerPhotoDocId('Road Case 1'): {'photoRef': ''},
        'road-case-1': {'photoRef': 'photos/old.jpg'},
      });

      expect(await service.readKey('Road Case 1'), 'photos/old.jpg');
    });

    test('writeKey writes the current id only', () async {
      final service = _FakeDocService({});

      await service.writeKey('Road Case 1', 'photos/new.jpg');

      expect(service.docs.keys, [containerPhotoDocId('Road Case 1')]);
    });

    test('clearKey deletes the legacy document too (#265)', () async {
      final service = _FakeDocService({
        containerPhotoDocId('Road Case 1'): {'photoRef': 'photos/new.jpg'},
        'road-case-1': {'photoRef': 'photos/old.jpg'},
      });

      await service.clearKey('Road Case 1');

      expect(service.docs, isEmpty);
      expect(await service.readKey('Road Case 1'), isNull);
    });
  });
}

class _FakeDocService extends FirestoreDocContainerPhotoSyncService {
  _FakeDocService(Map<String, Map<String, Object?>> seed) : docs = {...seed};

  final Map<String, Map<String, Object?>> docs;

  final List<String> deleted = [];

  @override
  Future<Map<String, Object?>?> readDoc(String docId) async => docs[docId];

  @override
  Future<void> setDoc(String docId, Map<String, Object?> fields) async =>
      docs[docId] = fields;

  @override
  Future<void> deleteDoc(String docId) async {
    deleted.add(docId);
    docs.remove(docId);
  }
}
