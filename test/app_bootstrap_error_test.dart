import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/app.dart';
import 'support/fake_borrow_sync_service.dart';
import 'support/fake_container_photo_sync_service.dart';
import 'support/fake_inventory_sync_service.dart';
import 'support/fake_map_image_store.dart';
import 'support/fake_map_location_sync_service.dart';
import 'support/fake_packing_sync_service.dart';
import 'support/photo_test_support.dart';
import 'support/fake_pit_shift_sync_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/map_location_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';
import 'package:spectrumpit/src/state/theme_controller.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';

import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

class _FailingOnceAuth extends FakeSpectrumAuthService {
  bool failNext = true;

  @override
  Future<void> initialize() async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated storage failure');
    }
    return super.initialize();
  }
}

void main() {
  testWidgets('bootstrap failure shows the error screen and retry recovers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final auth = _FailingOnceAuth();

    await tester.pumpWidget(
      StrategyApp(
        authService: auth,
        themeController: ThemeController(),
        userRoleController: UserRoleController(
          authService: auth,
          roleService: FakeUserRoleService(),
        ),
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spectrum Pit could not start'), findsOneWidget);
    expect(find.textContaining('simulated storage failure'), findsOneWidget);

    final retry = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Try again'),
    );
    retry.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Spectrum Pit could not start'), findsNothing);
    expect(find.text('You do not have access.'), findsOneWidget);
  });
}
