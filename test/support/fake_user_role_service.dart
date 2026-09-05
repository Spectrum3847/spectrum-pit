import 'dart:async';

import 'package:spectrumpit/src/models/user_profile.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/user_role_service_interface.dart';

class FakeUserRoleService implements UserRoleService {
  final Map<String, Set<UserRole>> _roles = {};
  final Map<String, String> _displayNames = {};
  final Map<String, String> _emails = {};
  final StreamController<List<UserProfile>> _profiles =
      StreamController<List<UserProfile>>.broadcast();

  void setProfile(
    String uid, {
    String? displayName,
    String? email,
    Set<UserRole>? roles,
  }) {
    if (roles != null) _roles[uid] = roles;
    _roles.putIfAbsent(uid, () => {UserRole.viewer});
    if (displayName != null) _displayNames[uid] = displayName;
    if (email != null) _emails[uid] = email;
    _emitProfiles();
  }

  UserProfile profileFor(String uid) => UserProfile(
    uid: uid,
    displayName: _displayNames[uid] ?? uid,
    email: _emails[uid],
    roles: _roles[uid] ?? {UserRole.viewer},
  );

  void setRoles(String uid, Set<UserRole> roles) {
    _roles[uid] = roles;
    _emitProfiles();
  }

  void setRole(String uid, UserRole role) {
    _roles[uid] = {role};
    _emitProfiles();
  }

  @override
  Future<UserProfile> fetchOrCreateProfile({
    required String uid,
    String displayName = '',
    String? email,
  }) async {
    if (!_roles.containsKey(uid)) {
      _roles[uid] = {UserRole.pit};
      _emitProfiles();
    }

    _displayNames.putIfAbsent(uid, () => displayName);
    if (email != null) _emails.putIfAbsent(uid, () => email);
    return profileFor(uid);
  }

  @override
  Future<void> updateDisplayName(String uid, String displayName) async {
    _displayNames[uid] = displayName;
    _emitProfiles();
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
    final profiles = _roles.keys.map(profileFor).toList();

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
