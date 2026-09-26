import 'dart:async';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import 'spectrum_auth_service.dart';
import 'user_role_service_interface.dart';

class LocalOnlyAuthService implements SpectrumAuthService {
  LocalOnlyAuthService();

  static const SpectrumUser _localUser = SpectrumUser(
    uid: 'local',
    displayName: 'Local user',
  );
  static const SpectrumAuthSnapshot _snapshot = SpectrumAuthSnapshot(
    state: SpectrumAuthState.signedIn,
    user: _localUser,
  );

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _localUser;

  @override
  Future<String?> idToken() async => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> signIn() async {}

  @override
  Future<void> updateDisplayName(String displayName) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class LocalUserRoleService implements UserRoleService {
  @override
  Future<UserProfile> fetchOrCreateProfile({
    required String uid,
    String displayName = '',
    String? email,
  }) async => UserProfile(
    uid: uid,
    displayName: displayName,
    email: email,
    roles: const {UserRole.pit},
  );

  @override
  Future<void> updateDisplayName(String uid, String displayName) async {}

  @override
  Future<void> updateRoles(String targetUid, Set<UserRole> roles) async {}

  @override
  Stream<List<UserProfile>> streamAllProfiles() =>
      const Stream<List<UserProfile>>.empty();
}
