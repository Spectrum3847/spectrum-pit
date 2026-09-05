import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/user_role.dart';

import 'support/fake_borrow_sync_service.dart';
import 'support/fake_inventory_sync_service.dart';
import 'support/fake_map_image_store.dart';
import 'support/fake_map_location_sync_service.dart';
import 'support/fake_packing_sync_service.dart';
import 'support/photo_test_support.dart';
import 'support/fake_pit_shift_sync_service.dart';

import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/map_location_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';
import 'package:spectrumpit/src/state/theme_controller.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';
import 'package:spectrumpit/src/ui/app_shell.dart';

import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_container_photo_sync_service.dart';
import 'support/fake_user_role_service.dart';

Future<AppShell> _buildShell(
  WidgetTester tester, {
  SpectrumUser? signedInUser,
  Set<UserRole>? userRoles,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final auth = FakeSpectrumAuthService(initialUser: signedInUser);
  final theme = ThemeController();
  final roleService = FakeUserRoleService();
  if (signedInUser != null && userRoles != null) {
    roleService.setRoles(signedInUser.uid, userRoles);
  }
  final roles = UserRoleController(authService: auth, roleService: roleService);
  await roles.bootstrap();
  final inventoryController = InventoryController(
    authService: auth,
    syncService: FakeInventorySyncService(),
  );
  final packingController = PackingController(
    authService: auth,
    syncService: FakePackingSyncService(),
  );
  final borrowController = BorrowController(
    authService: auth,
    syncService: FakeBorrowSyncService(),
  );
  final mapLocationController = MapLocationController(
    authService: auth,
    syncService: FakeMapLocationSyncService(),
  );
  final pitShiftController = PitShiftController(
    authService: auth,
    syncService: FakePitShiftSyncService(),
  );

  final shell = AppShell(
    authService: auth,
    themeController: theme,
    userRoleController: roles,
    inventoryController: inventoryController,
    packingController: packingController,
    borrowController: borrowController,
    mapLocationController: mapLocationController,
    mapImageStore: FakeMapImageStore(),
    containerPhotoSyncService: FakeContainerPhotoSyncService(),
    photoService: unavailablePhotoService(),
    pitShiftController: pitShiftController,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: shell,
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  testWidgets('Viewer role (no user signed in) shows no-access screen', (
    tester,
  ) async {
    await _buildShell(tester);

    expect(find.text('Spectrum Pit'), findsOneWidget);
    expect(find.text('You do not have access.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    expect(
      find.widgetWithText(FilledButton, 'Sign in with Google'),
      findsOneWidget,
    );
  });

  testWidgets('Member role shows the feature tabs in the nav bar', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'pit-uid', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    expect(find.text('Spectrum Pit'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    final navBar = find.byType(NavigationBar);
    expect(
      find.descendant(of: navBar, matching: find.text('Inventory')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Packing')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Borrowed')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Maps')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Schedule')),
      findsOneWidget,
    );

    expect(
      find.descendant(of: navBar, matching: find.text('Docs')),
      findsNothing,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Settings')),
      findsNothing,
    );
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
  });

  testWidgets('Overflow menu holds Docs and Settings but not Users', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'pit-uid3', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Docs'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    expect(find.text('Users'), findsNothing);
  });

  testWidgets('Admin overflow menu adds Users', (tester) async {
    const user = SpectrumUser(uid: 'admin-uid', displayName: 'Admin');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.admin});

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    final navBar = find.byType(NavigationBar);
    for (final label in const [
      'Inventory',
      'Packing',
      'Borrowed',
      'Maps',
      'Schedule',
    ]) {
      expect(
        find.descendant(of: navBar, matching: find.text(label)),
        findsOneWidget,
        reason: '$label belongs in the bottom nav',
      );
    }

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Docs'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Feature destinations lay out at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = SpectrumUser(uid: 'admin-narrow', displayName: 'Admin');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.admin});

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Opening Settings from the overflow shows appearance', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'pit-uid2', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('Pushing a route off the shell does not trip the hero assert', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'pit-uid4', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('New user auto-gets pit and lands in the app', (tester) async {
    const user = SpectrumUser(uid: 'new-uid', displayName: 'New User');

    await _buildShell(tester, signedInUser: user);

    expect(find.text('You do not have access.'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Demoted viewer sees the no-access screen', (tester) async {
    const user = SpectrumUser(uid: 'demoted-uid', displayName: 'New User');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.viewer});

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('You do not have access.'), findsOneWidget);
    expect(
      find.text(
        'Ask an admin to set your roles from the Users tab (New User).',
      ),
      findsOneWidget,
    );

    expect(
      find.widgetWithText(FilledButton, 'Sign in with Google'),
      findsNothing,
    );
  });

  group('keyboard destination navigation', () {
    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    int selected(WidgetTester tester) =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    testWidgets('ctrl+] moves forward and ctrl+[ moves back', (tester) async {
      const user = SpectrumUser(uid: 'admin-uid', displayName: 'Admin');
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.admin},
      );

      expect(selected(tester), 0);

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(selected(tester), 1);

      await press(tester, LogicalKeyboardKey.bracketLeft);
      expect(selected(tester), 0);
    });

    testWidgets('it wraps at both ends rather than sticking', (tester) async {
      const user = SpectrumUser(uid: 'admin-uid', displayName: 'Admin');
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.admin},
      );
      final count = tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .length;

      await press(tester, LogicalKeyboardKey.bracketLeft);
      expect(selected(tester), count - 1);

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(selected(tester), 0);
    });
  });
}
