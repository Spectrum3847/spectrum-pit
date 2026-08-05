import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import 'user_role_service_interface.dart';

class FirestoreUserRoleService implements UserRoleService {
  FirestoreUserRoleService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Set<UserRole>> fetchOrCreateRoles({
    required String uid,
    String displayName = '',
    String? email,
  }) async {
    try {
      final ref = _firestore.collection('userProfiles').doc(uid);
      final doc = await ref.get();
      if (!doc.exists || doc.data() == null) {
        final data = <String, dynamic>{
          'uid': uid,
          'displayName': displayName,
          'email': ?email,
          'roles': ['viewer'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };

        try {
          await ref.set(data);
        } catch (_) {}
        return {UserRole.viewer};
      }
      return UserProfile.fromJson(uid, doc.data()!).roles;
    } catch (_) {
      try {
        final cached = await _firestore
            .collection('userProfiles')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        final data = cached.data();
        if (cached.exists && data != null) {
          return UserProfile.fromJson(uid, data).roles;
        }
      } catch (_) {}
      return {UserRole.viewer};
    }
  }

  @override
  Future<void> updateRoles(String targetUid, Set<UserRole> roles) async {
    await _firestore.collection('userProfiles').doc(targetUid).set({
      'roles': roles.map((r) => r.name).toList(),
    }, SetOptions(merge: true));
  }

  @override
  Stream<List<UserProfile>> streamAllProfiles() {
    return _firestore.collection('userProfiles').snapshots().map(_profilesFrom);
  }

  List<UserProfile> _profilesFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final profiles = snapshot.docs
        .map((doc) => UserProfile.fromJson(doc.id, doc.data()))
        .toList();
    profiles.sort(UserProfile.byDisplayName);
    return profiles;
  }
}
