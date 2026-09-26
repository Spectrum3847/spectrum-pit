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
  UserProfile? _profile;

  int _fetchGeneration = 0;

  Object? _rolesError;

  Set<UserRole> get roles => Set.unmodifiable(_roles);

  String? get currentUid => _currentUid;

  UserProfile? get profile => _profile;

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
        final profile = await _roleService.fetchOrCreateProfile(
          uid: user.uid,
          displayName: user.displayName,
          email: user.email,
        );
        if (gen == _fetchGeneration) {
          _profile = profile;
          _roles = profile.roles;
          _rolesError = null;
          notifyListeners();
          await _publishDisplayName();
        }
      } catch (error) {
        if (gen == _fetchGeneration) {
          _profile = null;
          _roles = {UserRole.viewer};
          _rolesError = error;
          notifyListeners();
        }
      }
    } else if (snapshot.state == SpectrumAuthState.signedOut) {
      ++_fetchGeneration;
      _currentUid = null;
      _profile = null;
      _roles = {UserRole.viewer};
      _rolesError = null;
      notifyListeners();
    }
  }

  Future<void> _publishDisplayName() async {
    final wanted = _profile?.displayName ?? '';
    if (wanted.isEmpty) return;
    if (_authService.currentUser?.displayName == wanted) return;
    try {
      await _authService.updateDisplayName(wanted);
    } catch (error) {
      debugPrint('Could not publish the display name: $error');
    }
  }

  Future<void> updateDisplayName(String targetUid, String newName) async {
    final trimmed = newName.trim();
    if (!canManageUsers) {
      throw StateError('Only admins can change a display name');
    }
    if (targetUid == _currentUid) {
      throw StateError('Admins cannot rename themselves via the GUI');
    }
    if (trimmed.isEmpty) {
      throw ArgumentError('A display name cannot be empty');
    }
    await _roleService.updateDisplayName(targetUid, trimmed);
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
