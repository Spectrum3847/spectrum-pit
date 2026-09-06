import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/user_role_service.dart';

void main() {
  group('fetchOrCreateProfile', () {
    test('creates a pit profile on first sign-in', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreUserRoleService(firestore: firestore);

      final profile = await service.fetchOrCreateProfile(
        uid: 'new-uid',
        displayName: 'New User',
      );

      expect(profile.roles, {UserRole.pit});
      final doc = await firestore
          .collection('userProfiles')
          .doc('new-uid')
          .get();
      expect(doc.data()!['roles'], ['pit']);
    });
  });
}
