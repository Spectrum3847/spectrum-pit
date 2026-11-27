import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/debug_no_auth.dart';
import 'package:spectrumpit/src/services/local_only_services.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';

void main() {
  test('LocalOnlyAuthService presents a signed-in local session', () async {
    final auth = LocalOnlyAuthService();
    addTearDown(auth.dispose);
    expect(auth.snapshot.state, SpectrumAuthState.signedIn);
    expect(auth.currentUser?.uid, 'local');

    expect(await auth.idToken(), isNull);
  });

  test('LocalUserRoleService grants the pit role (no admin)', () async {
    final profile = await LocalUserRoleService().fetchOrCreateProfile(
      uid: 'local',
    );
    final roles = profile.roles;
    expect(roles, {UserRole.pit});
    expect(roles.canManageUsers, isFalse);
    expect(await LocalUserRoleService().streamAllProfiles().toList(), isEmpty);
  });

  test(
    'local auth + role wiring yields a usable (non-viewer) session offline',
    () async {
      final auth = LocalOnlyAuthService();
      final controller = UserRoleController(
        authService: auth,
        roleService: LocalUserRoleService(),
      );
      addTearDown(() async {
        controller.dispose();
        await auth.dispose();
      });

      await controller.bootstrap();

      expect(controller.roles, {UserRole.pit});
      expect(controller.visibleTabIndices, isNotEmpty);
      expect(controller.canManageUsers, isFalse);

      await expectLater(
        controller.updateUserRoles('local', {UserRole.admin}),
        throwsStateError,
      );
    },
  );

  test('LocalUserRoleService grants the roles it is given', () async {
    final profile = await LocalUserRoleService(
      roles: {UserRole.admin, UserRole.developer},
    ).fetchOrCreateProfile(uid: 'local');
    expect(profile.roles, {UserRole.admin, UserRole.developer});
  });

  test('parseDebugRoles reads a comma-separated role list', () {
    expect(parseDebugRoles('developer'), {UserRole.developer});
    expect(parseDebugRoles(' Admin , developer,bogus'), {
      UserRole.admin,
      UserRole.developer,
    });
    expect(parseDebugRoles(''), defaultLocalRoles);
    expect(parseDebugRoles('bogus'), defaultLocalRoles);
  });

  test('debug no-auth mode is off without its define', () {
    expect(debugNoAuth, isFalse);
    expect(localSessionRoles, defaultLocalRoles);
  });
}
