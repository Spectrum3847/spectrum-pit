import '../models/user_profile.dart';
import '../models/user_role.dart';

abstract class UserRoleService {
  Future<UserProfile> fetchOrCreateProfile({
    required String uid,
    String displayName = '',
    String? email,
  });

  Future<void> updateDisplayName(String uid, String displayName);

  Future<void> updateRoles(String targetUid, Set<UserRole> roles);

  Stream<List<UserProfile>> streamAllProfiles();
}
