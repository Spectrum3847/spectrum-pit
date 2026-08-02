import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../services/spectrum_auth_service.dart';
import '../services/user_role_service.dart';

class UserRoleController extends ChangeNotifier {
  UserRoleController({
    required SpectrumAuthService authService,
    required UserRoleService roleService,
  }) : _authService = authService,
       _roleService = roleService;

  final SpectrumAuthService _authService;
  final UserRoleService _roleService;

  Future<void>? _bootstrapFuture;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  Set<UserRole> _roles = {UserRole.viewer};
  String? _currentUid;

  int _fetchGeneration = 0;

  Set<UserRole> get roles => Set.unmodifiable(_roles);

  String? get currentUid => _currentUid;

  bool get canManageUsers => _roles.canManageUsers;

  bool get isDebug => _roles.isDebug;

  List<int> get visibleTabIndices => _roles.visibleTabIndices;

  Future<void> bootstrap() {
    _bootstrapFuture ??= _doBootstrap();
    return _bootstrapFuture!;
  }

  Future<void> _doBootstrap() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthSnapshot);
    await _onAuthSnapshot(_authService.snapshot);
  }

  Future<void> _onAuthSnapshot(SpectrumAuthSnapshot snapshot) async {
    if (snapshot.state == SpectrumAuthState.signedIn && snapshot.user != null) {
      final user = snapshot.user!;
      _currentUid = user.uid;
      final gen = ++_fetchGeneration;
      final roles = await _roleService.fetchOrCreateRoles(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
      );
      if (gen == _fetchGeneration) {
        _roles = roles;
        notifyListeners();
      }
    } else if (snapshot.state == SpectrumAuthState.signedOut) {
      ++_fetchGeneration;
      _currentUid = null;
      _roles = {UserRole.viewer};
      notifyListeners();
    }
  }

  Future<void> updateUserRoles(String targetUid, Set<UserRole> newRoles) async {
    if (!canManageUsers) {
      throw StateError('Only admins can update user roles');
    }
    if (targetUid == _currentUid) {
      throw StateError('Admins cannot change their own roles via the GUI');
    }
    await _roleService.updateRoles(targetUid, newRoles);
  }

  Stream<List<UserProfile>> streamAllProfiles() {
    return _roleService.streamAllProfiles();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
