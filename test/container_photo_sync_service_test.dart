import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/services/container_photo_sync_service.dart';

void main() {
  group('containerPhotoDocId', () {
    test('slugs a plain location', () {
      expect(containerPhotoDocId('Road Case 1'), 'road-case-1');
    });

    test('collapses a slash so the doc id stays Firestore-safe', () {
      expect(containerPhotoDocId('Cart 1/Drawer 2'), 'cart-1-drawer-2');
    });

    test('lowercases mixed case', () {
      expect(containerPhotoDocId('Road CASE 1'), 'road-case-1');
    });

    test('trims leading and trailing whitespace', () {
      expect(containerPhotoDocId('  Cart 1  '), 'cart-1');
    });

    test('collapses runs of separators to one dash', () {
      expect(containerPhotoDocId('Cart 1 / Drawer 2'), 'cart-1-drawer-2');
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
    });
  });
}
