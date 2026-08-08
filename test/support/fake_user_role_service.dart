import 'dart:async';

import 'package:spectrumpit/src/models/user_profile.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/user_role_service_interface.dart';

class FakeUserRoleService implements UserRoleService {
  final Map<String, Set<UserRole>> _roles = {};
  final Map<String, String> _displayNames = {};
  final StreamController<List<UserProfile>> _profiles =
      StreamController<List<UserProfile>>.broadcast();

  void setRoles(String uid, Set<UserRole> roles) {
    _roles[uid] = roles;
    _emitProfiles();
  }

  void setRole(String uid, UserRole role) {
    _roles[uid] = {role};
    _emitProfiles();
  }

  @override
  Future<Set<UserRole>> fetchOrCreateRoles({
    required String uid,
    String displayName = '',
    String? email,
  }) async {
    if (!_roles.containsKey(uid)) {
      _roles[uid] = {UserRole.viewer};
      _displayNames[uid] = displayName;
      _emitProfiles();
    }
    return _roles[uid]!;
  }

  @override
  Future<void> updateRoles(String uid, Set<UserRole> roles) async {
    _roles[uid] = roles;
    _emitProfiles();
  }

  @override
  Stream<List<UserProfile>> streamAllProfiles() async* {
    yield _currentProfiles();
    yield* _profiles.stream;
  }

  List<UserProfile> _currentProfiles() {
    final profiles = _roles.entries
        .map(
          (e) => UserProfile(
            uid: e.key,
            displayName: _displayNames[e.key] ?? e.key,
            roles: e.value,
          ),
        )
        .toList();

    profiles.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return profiles;
  }

  void _emitProfiles() {
    if (_profiles.isClosed) return;
    _profiles.add(_currentProfiles());
  }
}
