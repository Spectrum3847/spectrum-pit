import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/services.dart' show PlatformException;

bool isPermissionDeniedError(Object error) {
  final errorText = error.toString().toLowerCase();
  return (error is FirebaseException && error.code == 'permission-denied') ||
      (error is PlatformException && error.code == 'permission-denied') ||
      (errorText.contains('permission') && errorText.contains('denied'));
}

String describeSyncError(String action, Object error) {
  if (isPermissionDeniedError(error)) {
    return 'The server refused to $action. Check your role with an admin.';
  }
  return 'Could not $action: $error';
}
