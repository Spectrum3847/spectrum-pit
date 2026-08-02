import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/local_only_services.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';

void main() {
  test('LocalOnlyAuthService presents a signed-in local session', () async {
    final auth = LocalOnlyAuthService();
    addTearDown(auth.dispose);
    expect(auth.snapshot.state, SpectrumAuthState.signedIn);
    expect(auth.currentUser?.uid, 'local');
    // The local session is synthetic, so anything needing a Firebase token
    // (the photo Worker) has to see null and degrade.
    expect(await auth.idToken(), isNull);
  });

  test('LocalUserRoleService grants the pit role (no admin)', () async {
    final roles = await LocalUserRoleService().fetchOrCreateRoles(uid: 'local');
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

      // Not the no-access viewer state: the offline user can see the app.
      expect(controller.roles, {UserRole.pit});
      expect(controller.visibleTabIndices, isNotEmpty);
      expect(controller.canManageUsers, isFalse);
    },
  );
}
