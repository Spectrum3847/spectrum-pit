import 'package:spectrumpit/src/models/user_profile.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/user_role_service.dart';

class FakeUserRoleService implements UserRoleService {
  final Map<String, Set<UserRole>> _roles = {};
  final Map<String, String> _displayNames = {};

  // Pre-set a specific role set for a UID. If not set, fetchOrCreateRoles
  // will auto-assign viewer (mirroring real first-sign-in behaviour: the
  // no-access default until an admin promotes the account, #334).
  void setRoles(String uid, Set<UserRole> roles) => _roles[uid] = roles;

  // Convenience wrapper for single-role tests.
  void setRole(String uid, UserRole role) => _roles[uid] = {role};

  @override
  Future<Set<UserRole>> fetchOrCreateRoles({
    required String uid,
    String displayName = '',
    String? email,
  }) async {
    if (!_roles.containsKey(uid)) {
      _roles[uid] = {UserRole.viewer};
      _displayNames[uid] = displayName;
    }
    return _roles[uid]!;
  }

  @override
  Future<void> updateRoles(String uid, Set<UserRole> roles) async {
    _roles[uid] = roles;
  }

  @override
  Stream<List<UserProfile>> streamAllProfiles() {
    return Stream.value(
      _roles.entries
          .map(
            (e) => UserProfile(
              uid: e.key,
              displayName: _displayNames[e.key] ?? e.key,
              roles: e.value,
            ),
          )
          .toList(),
    );
  }
}
