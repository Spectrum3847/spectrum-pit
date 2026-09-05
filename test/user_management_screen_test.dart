import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/models/user_profile.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';
import 'package:spectrumpit/src/ui/user_management_screen.dart';

import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

class _FlakyRoleService extends FakeUserRoleService {
  int streamCalls = 0;

  @override
  Stream<List<UserProfile>> streamAllProfiles() {
    streamCalls++;
    if (streamCalls == 1) {
      return Stream<List<UserProfile>>.error(StateError('poll failed'));
    }
    return super.streamAllProfiles();
  }
}

void main() {
  testWidgets('users error state offers a retry that resubscribes', (
    tester,
  ) async {
    final roleService = _FlakyRoleService()..setRole('u1', UserRole.admin);
    final controller = UserRoleController(
      authService: FakeSpectrumAuthService(),
      roleService: roleService,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(body: UserManagementBody(roleController: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load users'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load users'), findsNothing);
    expect(find.text('uid: u1'), findsOneWidget);
    expect(roleService.streamCalls, 2);
  });

  testWidgets('editing roles saves the new set through the service (#524)', (
    tester,
  ) async {
    final roleService = FakeUserRoleService()
      ..setRole('u1', UserRole.pit)
      ..setRole('admin-1', UserRole.admin);

    final controller = UserRoleController(
      authService: FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin-1', displayName: 'Admin'),
      ),
      roleService: roleService,
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(body: UserManagementBody(roleController: controller)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit roles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UserRole.developer.displayName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await roleService.fetchOrCreateProfile(uid: 'u1')).roles, {
      UserRole.pit,
      UserRole.developer,
    });
  });
}
