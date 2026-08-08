import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';

import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

void main() {
  const featureTabs = [
    AppTabs.inventory,
    AppTabs.packing,
    AppTabs.borrowed,
    AppTabs.maps,
    AppTabs.schedule,
  ];
  const pitTabs = [...featureTabs, AppTabs.docs, AppTabs.settings];
  const adminTabs = [
    ...featureTabs,
    AppTabs.docs,
    AppTabs.users,
    AppTabs.settings,
  ];

  group('UserRole.fromString', () {
    test('parses known role strings', () {
      expect(UserRole.fromString('viewer'), UserRole.viewer);
      expect(UserRole.fromString('pit'), UserRole.pit);
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('developer'), UserRole.developer);
    });

    test('falls back to viewer for unknown/null values', () {
      expect(UserRole.fromString(null), UserRole.viewer);
      expect(UserRole.fromString(''), UserRole.viewer);
      expect(UserRole.fromString('unknown'), UserRole.viewer);
    });
  });

  group('UserRole.tryParse', () {
    test('parses known role strings', () {
      expect(UserRole.tryParse('viewer'), UserRole.viewer);
      expect(UserRole.tryParse('pit'), UserRole.pit);
      expect(UserRole.tryParse('admin'), UserRole.admin);
      expect(UserRole.tryParse('developer'), UserRole.developer);
    });

    test('returns null for unknown/null values', () {
      expect(UserRole.tryParse(null), isNull);
      expect(UserRole.tryParse(''), isNull);
      expect(UserRole.tryParse('unknown'), isNull);
    });
  });

  group('UserRoleSetPermissions', () {
    test('viewer only: no tabs, no debug, no manage', () {
      final roles = {UserRole.viewer};
      expect(roles.visibleTabIndices, isEmpty);
      expect(roles.canManageUsers, isFalse);
      expect(roles.isDebug, isFalse);
    });

    test('pit: feature tabs + Docs + Settings', () {
      expect({UserRole.pit}.visibleTabIndices, pitTabs);
    });

    test('isMember: true for any non-viewer role, false for viewer only', () {
      expect({UserRole.viewer}.isMember, isFalse);
      expect({UserRole.pit}.isMember, isTrue);
      expect({UserRole.admin}.isMember, isTrue);
      expect({UserRole.developer}.isMember, isTrue);
      expect({UserRole.viewer, UserRole.pit}.isMember, isTrue);
    });

    test('admin: all tabs including Users, canManageUsers', () {
      final roles = {UserRole.admin};
      expect(roles.visibleTabIndices, adminTabs);
      expect(roles.canManageUsers, isTrue);
    });

    test('developer: feature tabs + Docs + Settings, no Users, isDebug', () {
      final roles = {UserRole.developer};
      expect(roles.visibleTabIndices, pitTabs);
      expect(roles.isDebug, isTrue);
      expect(roles.canManageUsers, isFalse);
    });

    test('multi-role union: pit + admin = all tabs', () {
      final roles = {UserRole.pit, UserRole.admin};
      expect(roles.visibleTabIndices, adminTabs);
      expect(roles.canManageUsers, isTrue);
    });

    test(
      'multi-role union: admin + developer = all tabs + isDebug + canManage',
      () {
        final roles = {UserRole.admin, UserRole.developer};
        expect(roles.visibleTabIndices, adminTabs);
        expect(roles.canManageUsers, isTrue);
        expect(roles.isDebug, isTrue);
      },
    );
  });

  group('UserRoleController', () {
    late FakeSpectrumAuthService auth;
    late FakeUserRoleService roles;

    setUp(() {
      auth = FakeSpectrumAuthService();
      roles = FakeUserRoleService();
    });

    test('starts as viewer when signed out', () async {
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      expect(controller.roles, {UserRole.viewer});
      controller.dispose();
    });

    test('auto-assigns viewer for new user with no profile', () async {
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-new',
        displayName: 'New User',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.viewer});
      controller.dispose();
    });

    test('fetches pre-set roles after sign-in', () async {
      roles.setRoles('uid-admin', {UserRole.admin, UserRole.developer});
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-admin',
        displayName: 'Admin Dev',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.admin, UserRole.developer});
      expect(controller.canManageUsers, isTrue);
      expect(controller.isDebug, isTrue);
      controller.dispose();
    });

    test('resets to viewer after sign-out', () async {
      roles.setRole('uid-pit', UserRole.pit);
      final initialUser = const SpectrumUser(
        uid: 'uid-pit',
        displayName: 'Pit User',
      );
      auth = FakeSpectrumAuthService(initialUser: initialUser);
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.pit});

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.viewer});
      expect(controller.currentUid, isNull);
      controller.dispose();
    });

    test('bootstrap is idempotent', () async {
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await Future.wait([controller.bootstrap(), controller.bootstrap()]);
      expect(controller.roles, {UserRole.viewer});
      controller.dispose();
    });

    test('notifies listeners when roles change', () async {
      roles.setRole('uid-pit', UserRole.pit);
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-pit',
        displayName: 'Pit User',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.pit});
      expect(notifyCount, greaterThan(0));
      controller.dispose();
    });

    test('updateUserRoles updates roles via service', () async {
      roles.setRole('uid-admin', UserRole.admin);
      roles.setRole('uid-target', UserRole.pit);
      final initialUser = const SpectrumUser(
        uid: 'uid-admin',
        displayName: 'Admin',
      );
      auth = FakeSpectrumAuthService(initialUser: initialUser);
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      await Future<void>.delayed(Duration.zero);

      expect(controller.canManageUsers, isTrue);

      await controller.updateUserRoles('uid-target', {
        UserRole.pit,
        UserRole.developer,
      });

      final profiles = await roles.streamAllProfiles().first;
      final target = profiles.firstWhere((p) => p.uid == 'uid-target');
      expect(target.roles, {UserRole.pit, UserRole.developer});
      controller.dispose();
    });

    test(
      'updateUserRoles throws for non-admins (release-mode guard)',
      () async {
        roles.setRole('uid-pit', UserRole.pit);
        auth = FakeSpectrumAuthService(
          initialUser: const SpectrumUser(uid: 'uid-pit', displayName: 'S'),
        );
        final controller = UserRoleController(
          authService: auth,
          roleService: roles,
        );
        await controller.bootstrap();
        await Future<void>.delayed(Duration.zero);

        await expectLater(
          controller.updateUserRoles('uid-x', {UserRole.pit}),
          throwsStateError,
        );
        controller.dispose();
      },
    );

    test('updateUserRoles throws for the admin\'s own uid', () async {
      roles.setRole('uid-admin', UserRole.admin);
      auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'uid-admin', displayName: 'A'),
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        controller.updateUserRoles('uid-admin', {UserRole.viewer}),
        throwsStateError,
      );
      controller.dispose();
    });
  });
}
