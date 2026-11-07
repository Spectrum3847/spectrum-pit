import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/sync_error.dart';

void main() {
  group('isPermissionDeniedError', () {
    test('true for a FirebaseException with the permission-denied code', () {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
      expect(isPermissionDeniedError(error), isTrue);
    });

    test('true for a PlatformException with the permission-denied code', () {
      final error = PlatformException(code: 'permission-denied');
      expect(isPermissionDeniedError(error), isTrue);
    });

    test('true for a text-only error naming permission and denied', () {
      expect(
        isPermissionDeniedError(Exception('403: permission denied')),
        isTrue,
      );
    });

    test('false for an unrelated error', () {
      expect(isPermissionDeniedError(Exception('Connection reset')), isFalse);
    });
  });

  group('describeSyncError', () {
    test('names a refusal distinctly from a generic failure', () {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      expect(
        describeSyncError('save "Drill"', error),
        'The server refused to save "Drill". Check your role with an admin.',
      );
    });

    test('falls back to the raw error for anything else', () {
      final error = Exception('Connection reset');
      expect(
        describeSyncError('save "Drill"', error),
        'Could not save "Drill": $error',
      );
    });
  });
}
