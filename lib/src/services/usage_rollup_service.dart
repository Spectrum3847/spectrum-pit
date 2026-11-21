import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/usage_rollup.dart';

abstract class UsageRollupService {
  Future<UsageRollup> fetch();
}

class UsageRollupUnavailable implements Exception {
  const UsageRollupUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

const String _docPath = 'telemetryRollup/current';

const _missing = UsageRollupUnavailable(
  'No usage rollup yet. The daily job writes it; if this persists, '
  'check the Usage rollup cron workflow.',
);

const _denied = UsageRollupUnavailable(
  'Usage data is limited to the developer role.',
);

class FirestoreUsageRollupService implements UsageRollupService {
  FirestoreUsageRollupService({this._firestore});

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<UsageRollup> fetch() async {
    try {
      final snapshot = await _db.doc(_docPath).get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) throw _missing;
      return UsageRollup.fromJson(data);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') throw _denied;
      throw UsageRollupUnavailable(
        'Could not read usage data: ${error.message ?? error.code}',
      );
    }
  }
}

class DesktopUsageRollupService implements UsageRollupService {
  DesktopUsageRollupService({required this._firestore});

  final fc.Firestore _firestore;

  @override
  Future<UsageRollup> fetch() async {
    try {
      final doc = await _firestore.getDocument(_docPath);
      if (doc == null) throw _missing;
      return UsageRollup.fromJson(doc.fields);
    } on fc.FirestoreApiException catch (error) {
      if (error.status == 'PERMISSION_DENIED' || error.statusCode == 403) {
        throw _denied;
      }
      throw UsageRollupUnavailable(
        'Could not read usage data: '
        '${error.message.isEmpty ? error.status : error.message}',
      );
    }
  }
}

class LocalUsageRollupService implements UsageRollupService {
  const LocalUsageRollupService();

  @override
  Future<UsageRollup> fetch() async => throw const UsageRollupUnavailable(
    'Usage data needs a signed-in session.',
  );
}
