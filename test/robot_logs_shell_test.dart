import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/map_location_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';
import 'package:spectrumpit/src/state/robot_logs_controller.dart';
import 'package:spectrumpit/src/state/scout_shift_mirror_controller.dart';
import 'package:spectrumpit/src/state/theme_controller.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';
import 'package:spectrumpit/src/ui/app_shell.dart';
import 'package:spectrumpit/src/ui/robot_logs_tab.dart';

import 'support/fake_borrow_sync_service.dart';
import 'support/fake_container_photo_sync_service.dart';
import 'support/fake_inventory_sync_service.dart';
import 'support/fake_map_image_store.dart';
import 'support/fake_map_location_sync_service.dart';
import 'support/fake_packing_sync_service.dart';
import 'support/fake_pit_shift_sync_service.dart';
import 'support/fake_scout_shift_mirror_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';
import 'support/photo_test_support.dart';

const _user = SpectrumUser(uid: 'u1', displayName: 'Tester');

Future<void> _pumpShell(
  WidgetTester tester, {
  RobotLogsController? robotLogs,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = FakeSpectrumAuthService(initialUser: _user);
  final roleService = FakeUserRoleService()
    ..setRoles(_user.uid, {UserRole.pit});
  final roles = UserRoleController(authService: auth, roleService: roleService);
  await roles.bootstrap();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: AppShell(
        authService: auth,
        themeController: ThemeController(),
        userRoleController: roles,
        inventoryController: InventoryController(
          authService: auth,
          syncService: FakeInventorySyncService(),
        ),
        packingController: PackingController(
          authService: auth,
          syncService: FakePackingSyncService(),
        ),
        borrowController: BorrowController(
          authService: auth,
          syncService: FakeBorrowSyncService(),
        ),
        mapLocationController: MapLocationController(
          authService: auth,
          syncService: FakeMapLocationSyncService(),
        ),
        mapImageStore: FakeMapImageStore(),
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
        photoService: unavailablePhotoService(),
        pitShiftController: PitShiftController(
          authService: auth,
          syncService: FakePitShiftSyncService(),
        ),
        scoutShiftMirrorController: ScoutShiftMirrorController(
          authService: auth,
          syncService: FakeScoutShiftMirrorSyncService(),
        ),
        robotLogsController: robotLogs,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Robot logs is a rail destination when a controller is given', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('robot_logs_shell');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = RobotLogsController(
      isOpen: (host, port) async => false,
      defaultFolder: '${dir.path}/logs',
    );
    await _pumpShell(tester, robotLogs: c);
    expect(find.text('Robot logs'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Robot logs'));
      await c.bootstrap();
    });
    await tester.pumpAndSettle();
    expect(find.byType(RobotLogsTab), findsOneWidget);
    expect(find.text('Pull and send everything new'), findsOneWidget);
  });

  testWidgets('Robot logs is hidden without a controller', (tester) async {
    await _pumpShell(tester);
    expect(find.text('Robot logs'), findsNothing);
  });
}
