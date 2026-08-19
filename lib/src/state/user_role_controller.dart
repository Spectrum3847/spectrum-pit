import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../services/spectrum_auth_service.dart';
import '../services/user_role_service_interface.dart';

class UserRoleController extends ChangeNotifier {
  UserRoleController({required this._authService, required this._roleService});

  final SpectrumAuthService _authService;
  final UserRoleService _roleService;

  Future<void>? _bootstrapFuture;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  Set<UserRole> _roles = {UserRole.viewer};
  String? _currentUid;

  int _fetchGeneration = 0;

  Object? _rolesError;

  Set<UserRole> get roles => Set.unmodifiable(_roles);

  String? get currentUid => _currentUid;

  Object? get rolesError => _rolesError;

  bool get canManageUsers => _roles.canManageUsers;

  bool get isDebug => _roles.isDebug;

  List<int> get visibleTabIndices => _roles.visibleTabIndices;

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _doBootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
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
      try {
        final roles = await _roleService.fetchOrCreateRoles(
          uid: user.uid,
          displayName: user.displayName,
          email: user.email,
        );
        if (gen == _fetchGeneration) {
          _roles = roles;
          _rolesError = null;
          notifyListeners();
        }
      } catch (error) {
        if (gen == _fetchGeneration) {
          _roles = {UserRole.viewer};
          _rolesError = error;
          notifyListeners();
        }
      }
    } else if (snapshot.state == SpectrumAuthState.signedOut) {
      ++_fetchGeneration;
      _currentUid = null;
      _roles = {UserRole.viewer};
      _rolesError = null;
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
