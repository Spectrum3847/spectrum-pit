import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/services/container_photo_sync_service.dart';
import 'package:spectrumpit/src/services/photo_service.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/ui/packing_tab.dart';

import 'support/fake_container_photo_sync_service.dart';
import 'support/fake_inventory_sync_service.dart';
import 'support/fake_packing_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/photo_test_support.dart';

const _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

PackingRecord _record(
  String id, {
  String itemId = 'Drill',
  PackingStatus status = PackingStatus.packing,
  String? photoRef,
}) => PackingRecord(
  id: id,
  itemId: itemId,
  packingStatus: status,
  photoRef: photoRef,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<PackingController> _makeController({
  List<PackingRecord> initial = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  sync = FakePackingSyncService();
  final controller = PackingController(
    authService: FakeSpectrumAuthService(initialUser: _user),
    syncService: sync,
  );

  addTearDown(controller.dispose);
  await controller.bootstrap();
  if (initial.isNotEmpty) sync.emit(initial);
  return controller;
}

InventoryItem _inventoryItem(String id, {String name = 'Impact Driver'}) =>
    InventoryItem(
      id: id,
      name: name,
      labLocation: 'CAB-A2',
      pitLocation: 'RC1-DB',
      status: InventoryStatus.inLab,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<InventoryController> _makeInventory({
  List<InventoryItem> initial = const [],
}) async {
  inventorySync = FakeInventorySyncService();
  final controller = InventoryController(
    authService: FakeSpectrumAuthService(initialUser: _user),
    syncService: inventorySync,
  );
  addTearDown(controller.dispose);
  await controller.bootstrap();
  if (initial.isNotEmpty) inventorySync.emit(initial);
  return controller;
}

Widget _wrap(
  PackingController controller,
  InventoryController inventoryController, {
  PhotoService? photoService,
  required ContainerPhotoSyncService containerPhotoSyncService,
}) => MaterialApp(
  theme: ThemeData(splashFactory: NoSplash.splashFactory),
  home: Scaffold(
    body: PackingTab(
      controller: controller,
      inventoryController: inventoryController,
      photoService: photoService ?? unavailablePhotoService(),
      containerPhotoSyncService: containerPhotoSyncService,
    ),
  ),
);

late FakePackingSyncService sync;
late FakeInventorySyncService inventorySync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state shows the dashed board and add button', (
    tester,
  ) async {
    final controller = await _makeController();
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The packing list is empty'), findsOneWidget);
    expect(find.text('Add item'), findsWidgets);
  });

  testWidgets('items are displayed in a list', (tester) async {
    final controller = await _makeController(
      initial: [
        _record('a', itemId: 'Drill Kit'),
        _record('b', itemId: 'Soldering Iron'),
      ],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drill Kit'), findsOneWidget);
    expect(find.text('Soldering Iron'), findsOneWidget);
  });

  testWidgets('status chip shows the correct label', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', status: PackingStatus.staging)],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Staging'), findsOneWidget);
  });

  testWidgets('tapping status chip advances the pipeline', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', status: PackingStatus.packing)],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Packing'), findsOneWidget);
    await tester.tap(find.text('Packing'));
    await tester.pumpAndSettle();

    expect(controller.items.single.packingStatus, PackingStatus.staging);
    expect(find.text('Staging'), findsOneWidget);
    expect(sync.upserts, isNotEmpty);
  });

  testWidgets('FAB opens the add editor', (tester) async {
    final controller = await _makeController();
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add packing item'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('add editor creates a new record', (tester) async {
    final controller = await _makeController();
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Wrench Set');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add item').last);
    await tester.pumpAndSettle();

    expect(controller.items.length, 1);
    expect(controller.items.single.itemId, 'Wrench Set');
  });

  testWidgets('add button is disabled when name is empty', (tester) async {
    final controller = await _makeController();
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add item').last,
    );

    expect(button.onPressed, isNull);
  });

  testWidgets('tapping a row opens the edit editor', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', itemId: 'Drill')],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drill'));
    await tester.pumpAndSettle();

    expect(find.text('Edit packing item'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('a record with no photo shows the capture affordance', (
    tester,
  ) async {
    final controller = await _makeController(initial: [_record('a')]);
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
    expect(find.byTooltip('Add a packing photo'), findsOneWidget);
  });

  testWidgets('an attached photo renders as a thumbnail', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        photoService: fakePhotoService(stored: {'a.jpg': tinyPng}),
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
    expect(find.byTooltip('Open the packing photo'), findsOneWidget);
  });

  testWidgets('a photo that will not load offers a retry', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        photoService: fakePhotoService(
          respond: (_) => http.Response('boom', 500),
        ),
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(
      find.byTooltip('Photo did not load. Tap to try again.'),
      findsOneWidget,
    );
  });

  testWidgets('photos degrade to an unavailable slot with no ID token', (
    tester,
  ) async {
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('tapping the empty slot captures and attaches the photo', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = await _makeController(initial: [_record('a')]);
      final inventory = await _makeInventory();
      await tester.pumpWidget(
        _wrap(
          controller,
          inventory,
          photoService: fakePhotoService(
            picker: (_) async =>
                PickedPhoto(bytes: tinyPng, contentType: 'image/png'),
          ),
          containerPhotoSyncService: FakeContainerPhotoSyncService(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_a_photo_outlined));
      await tester.pumpAndSettle();

      expect(controller.items.single.photoRef, 'key-0.jpg');
      expect(find.byType(Image), findsOneWidget);
      expect(sync.upserts, isNotEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the viewer removes the photo and its stored key', (
    tester,
  ) async {
    final stored = {'a.jpg': tinyPng};
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        photoService: fakePhotoService(stored: stored),
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open the packing photo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Replace'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(controller.items.single.photoRef, isNull);
    expect(stored, isEmpty);
  });

  testWidgets('delete button removes the record', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', itemId: 'Drill')],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drill'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(controller.items, isEmpty);
  });

  testWidgets('a photo captured in the add editor lands on the new record', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = await _makeController();
      final inventory = await _makeInventory();
      await tester.pumpWidget(
        _wrap(
          controller,
          inventory,
          photoService: fakePhotoService(
            picker: (_) async =>
                PickedPhoto(bytes: tinyPng, contentType: 'image/png'),
          ),
          containerPhotoSyncService: FakeContainerPhotoSyncService(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add packing item'), findsOneWidget);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Wrench Set');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add item').last);
      await tester.pumpAndSettle();

      expect(controller.items.length, 1);
      expect(controller.items.single.itemId, 'Wrench Set');
      expect(controller.items.single.photoRef, 'key-0.jpg');
      expect(sync.upserts, isNotEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an inventory item with no record shows as a not-started row', (
    tester,
  ) async {
    final controller = await _makeController();
    final inventory = await _makeInventory(initial: [_inventoryItem('inv-1')]);
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Impact Driver'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);

    expect(controller.items, isEmpty);
  });

  testWidgets('a legacy record with no matching inventory item still renders', (
    tester,
  ) async {
    final controller = await _makeController(
      initial: [_record('legacy-1', itemId: 'Old free-text tool')],
    );
    final inventory = await _makeInventory();
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Old free-text tool'), findsOneWidget);
  });

  testWidgets('tapping a not-started row creates a real record', (
    tester,
  ) async {
    final controller = await _makeController();
    final inventory = await _makeInventory(initial: [_inventoryItem('inv-1')]);
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not started'));
    await tester.pumpAndSettle();

    expect(controller.items.length, 1);
    expect(controller.items.single.itemId, 'inv-1');
    expect(controller.items.single.id, 'inv-1');
    expect(controller.items.single.packingStatus, PackingStatus.packing);
    expect(sync.upserts, isNotEmpty);
    expect(find.text('Impact Driver'), findsOneWidget);
    expect(find.text('Packing'), findsOneWidget);
  });

  testWidgets(
    'saving a not-started row from the editor uses the item id, not a '
    'fresh one',
    (tester) async {
      final controller = await _makeController();
      final inventory = await _makeInventory(
        initial: [_inventoryItem('inv-1')],
      );
      await tester.pumpWidget(
        _wrap(
          controller,
          inventory,
          containerPhotoSyncService: FakeContainerPhotoSyncService(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Impact Driver'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add item'));
      await tester.pumpAndSettle();

      expect(controller.items.length, 1);
      expect(controller.items.single.id, 'inv-1');
      expect(controller.items.single.itemId, 'inv-1');
    },
  );

  testWidgets('items sharing a pitLocation render one location header', (
    tester,
  ) async {
    final controller = await _makeController();
    final inventory = await _makeInventory(
      initial: [
        _inventoryItem('inv-1', name: 'Impact Driver'),
        _inventoryItem('inv-2', name: 'Angle Grinder'),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RC1-DB'), findsOneWidget);
    expect(find.text('Impact Driver'), findsOneWidget);
    expect(find.text('Angle Grinder'), findsOneWidget);
  });

  testWidgets('the header photo affordance flips when readKey finds a photo', (
    tester,
  ) async {
    final controller = await _makeController();
    final inventory = await _makeInventory(initial: [_inventoryItem('inv-1')]);
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(
          seed: const {'RC1-DB': 'containers/rc1-db.jpg'},
        ),
      ),
    );

    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.byTooltip('Add a container photo'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    expect(find.byTooltip('Open the container photo'), findsOneWidget);
  });

  testWidgets(
    'a failed container photo read shows the offline state and tapping it retries',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final controller = await _makeController();
        final inventory = await _makeInventory(
          initial: [_inventoryItem('inv-1')],
        );
        final syncService = FakeContainerPhotoSyncService(
          readFailure: Exception('offline'),
        );
        var pickerOpened = false;
        final photoService = fakePhotoService(
          picker: (_) async {
            pickerOpened = true;
            return PickedPhoto(bytes: tinyPng, contentType: 'image/png');
          },
        );
        await tester.pumpWidget(
          _wrap(
            controller,
            inventory,
            photoService: photoService,
            containerPhotoSyncService: syncService,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
        expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
        expect(
          find.byTooltip(
            'Could not check for a container photo -- tap to retry',
          ),
          findsOneWidget,
        );
        expect(syncService.readCalls.length, 1);

        await tester.tap(find.byIcon(Icons.cloud_off_rounded));
        await tester.pumpAndSettle();

        expect(syncService.readCalls.length, 2);
        expect(pickerOpened, isFalse);
        expect(syncService.writeCalls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('replacing an existing container photo deletes the old key', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = await _makeController();
      final inventory = await _makeInventory(
        initial: [_inventoryItem('inv-1')],
      );
      final stored = {'rc1-db.jpg': tinyPng};
      final syncService = FakeContainerPhotoSyncService(
        seed: const {'RC1-DB': 'rc1-db.jpg'},
      );
      await tester.pumpWidget(
        _wrap(
          controller,
          inventory,
          photoService: fakePhotoService(
            stored: stored,
            picker: (_) async =>
                PickedPhoto(bytes: tinyPng, contentType: 'image/png'),
          ),
          containerPhotoSyncService: syncService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open the container photo'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Replace'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Replace'));
      await tester.pumpAndSettle();

      expect(syncService.writeCalls.single.location, 'RC1-DB');
      expect(syncService.writeCalls.single.key, isNot('rc1-db.jpg'));
      expect(stored.containsKey('rc1-db.jpg'), isFalse);
      expect(stored.containsKey('key-0.jpg'), isTrue);
      expect(find.byTooltip('Open the container photo'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a read landing after a replacement does not undo it (#266)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = await _makeController();
      final inventory = await _makeInventory(
        initial: [_inventoryItem('inv-1')],
      );
      final stored = {'old.jpg': tinyPng};

      final held = Completer<void>();
      final syncService = FakeContainerPhotoSyncService(
        seed: const {'RC1-DB': 'old.jpg'},
        onReadKey: (_) => held.future,
      );
      await tester.pumpWidget(
        _wrap(
          controller,
          inventory,
          photoService: fakePhotoService(
            stored: stored,
            picker: (_) async =>
                PickedPhoto(bytes: tinyPng, contentType: 'image/png'),
          ),
          containerPhotoSyncService: syncService,
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Add a container photo'));
      await tester.pumpAndSettle();
      expect(syncService.writeCalls.single.key, 'key-0.jpg');

      held.complete();
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open the container photo'), findsOneWidget);
      await tester.tap(find.byTooltip('Open the container photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(stored.containsKey('key-0.jpg'), isFalse);
      expect(syncService.clearCalls, ['RC1-DB']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an item with an empty pitLocation gets no location header', (
    tester,
  ) async {
    final controller = await _makeController();
    final inventory = await _makeInventory(
      initial: [
        InventoryItem(
          id: 'inv-1',
          name: 'Loose Wrench',
          labLocation: '',
          pitLocation: '',
          status: InventoryStatus.inLab,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        controller,
        inventory,
        containerPhotoSyncService: FakeContainerPhotoSyncService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loose Wrench'), findsOneWidget);
    expect(find.byTooltip('Add a container photo'), findsNothing);
  });
}
