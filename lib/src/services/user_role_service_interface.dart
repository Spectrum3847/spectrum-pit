import '../models/user_profile.dart';
import '../models/user_role.dart';

abstract class UserRoleService {
  Future<Set<UserRole>> fetchOrCreateRoles({
    required String uid,
    String displayName = '',
    String? email,
  });

  Future<void> updateRoles(String targetUid, Set<UserRole> roles);

  Stream<List<UserProfile>> streamAllProfiles();
}
