import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/borrow_tab.dart';
import 'package:spectrumpit/src/ui/inventory_tab.dart';
import 'package:spectrumpit/src/ui/packing_tab.dart';

import 'support/fake_borrow_sync_service.dart';
import 'support/fake_container_photo_sync_service.dart';
import 'support/fake_inventory_sync_service.dart';
import 'support/fake_packing_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/photo_test_support.dart';

const SpectrumUser _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');
const Size _smallPhone = Size(360, 760);
const TextScaler _doubled = TextScaler.linear(2.0);

Future<void> _pumpAtDoubleText(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = _smallPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkAppTheme(),

      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: _doubled),
        child: child!,
      ),
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the inventory tab holds up at 200% text', (tester) async {
    final sync = FakeInventorySyncService();
    final controller = InventoryController(
      authService: FakeSpectrumAuthService(initialUser: _user),
      syncService: sync,
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();
    sync.emit(<InventoryItem>[
      InventoryItem(
        id: 'a',
        name: 'Cordless drill with the long chuck',
        labLocation: 'RC1-DB',
        pitLocation: 'CAB-A2',
        status: InventoryStatus.inLab,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);

    await _pumpAtDoubleText(tester, InventoryTab(controller: controller));

    expect(find.text('Cordless drill with the long chuck'), findsOneWidget);
    expect(find.text('RC1-DB'), findsOneWidget);
    expect(find.text('CAB-A2'), findsOneWidget);
  });

  testWidgets('the borrow tab holds up at 200% text', (tester) async {
    final sync = FakeBorrowSyncService();
    final controller = BorrowController(
      authService: FakeSpectrumAuthService(initialUser: _user),
      syncService: sync,
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();
    sync.emit(<BorrowRecord>[
      BorrowRecord(
        id: 'a',
        toolName: 'Rivet gun',
        teamName: 'The Cheesy Poofs',
        teamNumber: 254,
        competition: 'Texas States',
        checkedOutAt: DateTime.utc(2026, 3, 1, 10),
        estimatedReturn: DateTime.utc(2026, 3, 1, 14),
        returned: false,
        updatedAt: DateTime.utc(2026, 3, 1, 10),
      ),
    ]);

    await _pumpAtDoubleText(tester, BorrowTab(controller: controller));

    expect(find.text('Rivet gun'), findsOneWidget);

    expect(
      find.textContaining('The Cheesy Poofs', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Texas States', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('the packing tab holds up at 200% text', (tester) async {
    final sync = FakePackingSyncService();
    final controller = PackingController(
      authService: FakeSpectrumAuthService(initialUser: _user),
      syncService: sync,
    );
    addTearDown(controller.dispose);
    await controller.bootstrap();
    sync.emit(<PackingRecord>[
      PackingRecord(
        id: 'a',
        itemId: 'Battery cart and its charger shelf',
        packingStatus: PackingStatus.packing,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    final inventorySync = FakeInventorySyncService();
    final inventoryController = InventoryController(
      authService: FakeSpectrumAuthService(initialUser: _user),
      syncService: inventorySync,
    );
    addTearDown(inventoryController.dispose);
    await inventoryController.bootstrap();

    await _pumpAtDoubleText(
      tester,
      PackingTab(
        controller: controller,
        inventoryController: inventoryController,
        photoService: unavailablePhotoService(),
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );

    expect(find.text('Battery cart and its charger shelf'), findsOneWidget);
  });
}
