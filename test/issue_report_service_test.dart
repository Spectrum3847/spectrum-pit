import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/issue_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('submit writes a bugReports doc matching the rules whitelist', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    await service.submit(
      title: '  Board did not save  ',
      body: '  Steps to reproduce  ',
      reporterUid: 'uid-123',
      reporterName: 'Jane Scout',
    );

    final snap = await firestore.collection('bugReports').get();
    expect(snap.docs, hasLength(1));
    final data = snap.docs.single.data();

    // Only the keys the Firestore rules' isValidBugReport allows.
    expect(data.keys.toSet(), {
      'id',
      'title',
      'body',
      'reporterUid',
      'reporterName',
      'appVersion',
      'platform',
      'osVersion',
      'deviceInfo',
      'status',
      'createdAt',
    });
    // Trimmed text and required invariants.
    expect(data['title'], 'Board did not save');
    expect(data['body'], 'Steps to reproduce');
    expect(data['reporterUid'], 'uid-123');
    expect(data['reporterName'], 'Jane Scout');
    expect(data['status'], 'new');
    expect(data['id'], snap.docs.single.id);
    // createdAt is an ISO-8601 UTC string inside the rules' century bounds.
    final createdAt = data['createdAt'] as String;
    expect(createdAt.startsWith('20'), isTrue);
    expect(DateTime.tryParse(createdAt), isNotNull);
  });

  test('submit records the reporter roles when provided (#500)', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
      roles: 'Admin, Pit',
    );

    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect(data['roles'], 'Admin, Pit');
    // Still only whitelisted keys, now including roles.
    expect(data.keys.contains('roles'), isTrue);
  });

  test('submit omits roles when none are granted', () async {
    final firestore = FakeFirebaseFirestore();
    final service = IssueReportService(firestore: firestore);

    await service.submit(
      title: 't',
      body: 'b',
      reporterUid: 'u',
      reporterName: 'n',
    );

    final data = (await firestore.collection('bugReports').get()).docs.single
        .data();
    expect(data.containsKey('roles'), isFalse);
  });

  test(
    'submit clamps an over-long title and body to the rule bounds',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = IssueReportService(firestore: firestore);

      await service.submit(
        title: 'x' * 500,
        body: 'y' * 8000,
        reporterUid: 'u',
        reporterName: 'n',
      );

      final data = (await firestore.collection('bugReports').get()).docs.single
          .data();
      expect((data['title'] as String).length, 200);
      expect((data['body'] as String).length, 4096);
    },
  );

  test(
    'an injected writer gets the same doc, without FlutterFire (#570)',
    () async {
      String? path;
      Map<String, dynamic>? written;
      final service = IssueReportService(
        write: (docPath, data) async {
          path = docPath;
          written = data;
        },
      );

      await service.submit(
        title: 'Linux report',
        body: 'sent over REST',
        reporterUid: 'uid-9',
        reporterName: 'Desk Top',
      );

      expect(path, 'bugReports/${written!['id']}');
      expect(written!['title'], 'Linux report');
      expect(written!['reporterUid'], 'uid-9');
      expect(written!['status'], 'new');
    },
  );
}
