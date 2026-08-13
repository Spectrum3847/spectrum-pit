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
}
