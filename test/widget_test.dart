import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/user_role.dart';

import 'support/fake_borrow_sync_service.dart';
import 'support/fake_inventory_sync_service.dart';
import 'support/fake_map_image_store.dart';
import 'support/fake_map_location_sync_service.dart';
import 'support/fake_packing_sync_service.dart';
import 'support/photo_test_support.dart';
import 'support/fake_pit_shift_sync_service.dart';
import 'support/fake_scout_shift_mirror_sync_service.dart';

import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/map_location_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';
import 'package:spectrumpit/src/state/scout_shift_mirror_controller.dart';
import 'package:spectrumpit/src/state/theme_controller.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';
import 'package:spectrumpit/src/ui/app_shell.dart';
import 'package:spectrumpit/src/ui/welcome_tour.dart';

import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_container_photo_sync_service.dart';
import 'support/fake_tour_service.dart';
import 'support/fake_user_role_service.dart';

Future<AppShell> _buildShell(
  WidgetTester tester, {
  SpectrumUser? signedInUser,
  Set<UserRole>? userRoles,
  FakeTourService? tourService,
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
  final scoutShiftMirrorController = ScoutShiftMirrorController(
    authService: auth,
    syncService: FakeScoutShiftMirrorSyncService(),
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
    scoutShiftMirrorController: scoutShiftMirrorController,
    tourService: tourService,
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

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder inBar(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('Phone bar leads with Now and puts the rest under More', (
    tester,
  ) async {
    usePhone(tester);
    const user = SpectrumUser(uid: 'pit-uid', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    expect(find.text('Spectrum Pit'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final label in const [
      'Now',
      'Inventory',
      'Packing',
      'Borrowed',
      'More',
    ]) {
      expect(inBar(label), findsOneWidget, reason: '$label is in the bar');
    }
    expect(inBar('Maps'), findsNothing);
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Find a tool'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More sheet holds the other tabs but not Users for pit', (
    tester,
  ) async {
    usePhone(tester);
    const user = SpectrumUser(uid: 'pit-uid3', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    await tester.tap(inBar('More'));
    await tester.pumpAndSettle();

    for (final label in const ['Maps', 'Schedule', 'Docs', 'Settings']) {
      expect(
        find.widgetWithText(ListTile, label),
        findsOneWidget,
        reason: '$label is under More',
      );
    }
    expect(find.widgetWithText(ListTile, 'Users'), findsNothing);
  });

  testWidgets('Admin More sheet adds Users', (tester) async {
    usePhone(tester);
    const user = SpectrumUser(uid: 'admin-uid', displayName: 'Admin');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.admin});

    await tester.tap(inBar('More'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Users'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Opening Settings from More shows appearance and selects More', (
    tester,
  ) async {
    usePhone(tester);
    const user = SpectrumUser(uid: 'pit-uid2', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    await tester.tap(inBar('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, bar.destinations.length - 1);
  });

  testWidgets('Tablet width shows a rail with every tab', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const user = SpectrumUser(uid: 'pit-tab', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, 8);
    expect(rail.extended, isFalse);
    expect(find.byTooltip('Collapse sidebar'), findsNothing);
  });

  testWidgets('Desktop sidebar collapses and remembers it', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const user = SpectrumUser(uid: 'pit-desk', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    NavigationRail rail() =>
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail().extended, isTrue);

    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();

    expect(rail().extended, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('app_sidebar_expanded'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A tab keeps its state when the window crosses into a rail', (
    tester,
  ) async {
    usePhone(tester);
    const user = SpectrumUser(uid: 'pit-resize', displayName: 'Pit');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.pit});

    await tester.tap(inBar('Inventory'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'wrench');
    await tester.pump();

    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('wrench'), findsOneWidget);
  });

  testWidgets('Picking a tool in the jump opens Inventory filtered to it', (
    tester,
  ) async {
    usePhone(tester);
    const user = SpectrumUser(uid: 'pit-jump', displayName: 'Pit');
    final shell = await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.pit},
    );
    await shell.inventoryController.upsert(
      InventoryItem(
        id: 'torque',
        name: 'Torque wrench',
        labLocation: 'L-A3',
        pitLocation: 'P-2',
        status: InventoryStatus.inPit,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Find a tool'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'torque');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Torque wrench').last);
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 1);
    expect(find.widgetWithText(TextField, 'Torque wrench'), findsOneWidget);
  });

  group('Welcome tour', () {
    const user = SpectrumUser(uid: 'pit-tour', displayName: 'Pit');

    testWidgets('first launch shows it and Skip persists', (tester) async {
      usePhone(tester);
      final tour = FakeTourService();
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.pit},
        tourService: tour,
      );

      expect(find.text('Welcome to Spectrum Pit'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeTourOverlay), findsNothing);
      expect(tour.seen, isTrue);
    });

    testWidgets('does not show once seen', (tester) async {
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.pit},
        tourService: FakeTourService(seen: true),
      );
      expect(find.byType(WelcomeTourOverlay), findsNothing);
    });

    testWidgets('losing access mid-tour drops it', (tester) async {
      usePhone(tester);
      final tour = FakeTourService();
      final shell = await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.pit},
        tourService: tour,
      );
      expect(find.byType(WelcomeTourOverlay), findsOneWidget);
      final auth = shell.authService as FakeSpectrumAuthService;
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('You do not have access.'), findsOneWidget);

      tour.seen = true;
      auth.nextSignInUser = user;
      await auth.signIn();
      await tester.pumpAndSettle();
      expect(find.text('You do not have access.'), findsNothing);
      expect(find.byType(WelcomeTourOverlay), findsNothing);
    });

    testWidgets('a viewer never sees it', (tester) async {
      await _buildShell(tester, tourService: FakeTourService());
      expect(find.byType(WelcomeTourOverlay), findsNothing);
    });

    testWidgets('Next switches to the tab each step describes', (tester) async {
      usePhone(tester);
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.pit},
        tourService: FakeTourService(),
      );

      NavigationBar bar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(bar().selectedIndex, 0);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(bar().selectedIndex, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('walks every step to Done on a tablet rail', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tour = FakeTourService();
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.pit},
        tourService: tour,
      );

      final rail = tester.getRect(find.byType(NavigationRail));
      final card = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
      expect(card.left, greaterThanOrEqualTo(rail.right));

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Settings'), findsWidgets);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeTourOverlay), findsNothing);
      expect(tour.seen, isTrue);

      final rail2 = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail2.selectedIndex, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Escape dismisses it', (tester) async {
      final tour = FakeTourService();
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.pit},
        tourService: tour,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeTourOverlay), findsNothing);
      expect(tour.seen, isTrue);
    });

    testWidgets('Settings replays it from the first tab', (tester) async {
      usePhone(tester);
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.pit},
        tourService: FakeTourService(seen: true),
      );

      await tester.tap(inBar('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Replay tour'), 200);
      await tester.tap(find.text('Replay tour'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Spectrum Pit'), findsOneWidget);
      NavigationBar bar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar().selectedIndex, 0);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(bar().selectedIndex, bar().destinations.length - 1);
      expect(find.text('Replay tour'), findsOneWidget);
    });
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
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('Demoted viewer sees the no-access screen', (tester) async {
    const user = SpectrumUser(uid: 'demoted-uid', displayName: 'New User');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.viewer});

    expect(find.byType(NavigationRail), findsNothing);
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

    int? selected(WidgetTester tester) => tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .selectedIndex;

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
          .widget<NavigationRail>(find.byType(NavigationRail))
          .destinations
          .length;

      await press(tester, LogicalKeyboardKey.bracketLeft);
      expect(selected(tester), count - 1);

      await press(tester, LogicalKeyboardKey.bracketRight);
      expect(selected(tester), 0);
    });
  });
}
