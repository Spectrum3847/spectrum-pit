import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/map_location.dart';
import 'package:spectrumpit/src/services/map_image_store.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/map_location_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/maps_tab.dart';

import 'support/fake_inventory_sync_service.dart';
import 'support/fake_map_image_store.dart';
import 'support/fake_map_location_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

MapLocation _pin(
  String id, {
  String name = 'Pin',
  MapType mapType = MapType.lab,
  double x = 0.5,
  double y = 0.5,
  String? inventoryItemId,
}) => MapLocation(
  id: id,
  name: name,
  mapType: mapType,
  x: x,
  y: y,
  inventoryItemId: inventoryItemId,
  updatedAt: DateTime.utc(2026, 1, 1),
);

InventoryItem _item(
  String id, {
  required String name,
  String lab = '',
  String pit = '',
}) => InventoryItem(
  id: id,
  name: name,
  labLocation: lab,
  pitLocation: pit,
  status: InventoryStatus.inLab,
  updatedAt: DateTime.utc(2026, 1, 1),
);

const _diagramSize = Size(1000, 600);

final Uint8List _transparentPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

MapDiagram _fakeDiagram({Size size = _diagramSize}) =>
    MapDiagram(image: MemoryImage(_transparentPng), size: size);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMapLocationSyncService mapSync;
  late FakeInventorySyncService inventorySync;
  late FakeMapImageStore imageStore;
  late MapLocationController mapController;
  late InventoryController inventoryController;

  setUp(() {
    mapSync = FakeMapLocationSyncService();
    inventorySync = FakeInventorySyncService();
    imageStore = FakeMapImageStore();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    List<MapLocation> pins = const <MapLocation>[],
    List<InventoryItem> items = const <InventoryItem>[],
  }) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeSpectrumAuthService(initialUser: _signedInUser);
    mapController = MapLocationController(
      authService: auth,
      syncService: mapSync,
    );
    inventoryController = InventoryController(
      authService: auth,
      syncService: inventorySync,
    );

    addTearDown(mapController.dispose);
    addTearDown(inventoryController.dispose);
    await mapController.bootstrap();
    await inventoryController.bootstrap();
    if (pins.isNotEmpty) mapSync.emit(pins);
    if (items.isNotEmpty) inventorySync.emit(items);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: Scaffold(
          body: MapsTab(
            controller: mapController,
            inventoryController: inventoryController,
            imageStore: imageStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no diagram set shows the empty state with a choose button', (
    tester,
  ) async {
    await pumpTab(tester);

    expect(find.text('No lab diagram set'), findsOneWidget);
    expect(find.text('Choose diagram'), findsOneWidget);
  });

  testWidgets('unsupported (web) empty state has no choose button', (
    tester,
  ) async {
    imageStore.isSupported = false;
    await pumpTab(tester);

    expect(
      find.textContaining('not supported in the browser preview'),
      findsOneWidget,
    );
    expect(find.text('Choose diagram'), findsNothing);
  });

  testWidgets('renders a pin per location once the diagram is set', (
    tester,
  ) async {
    imageStore.images[MapType.lab] = _fakeDiagram();

    await pumpTab(
      tester,
      pins: [
        _pin('a', name: 'Battery cart', x: 0.2, y: 0.3),
        _pin('b', name: 'Charging station', x: 0.7, y: 0.6),

        _pin('c', name: 'Pit-only pin', mapType: MapType.pit),
      ],
    );

    expect(find.text('No lab diagram set'), findsNothing);
    expect(find.byIcon(Icons.location_on_outlined), findsNWidgets(2));
  });

  testWidgets('the diagram and its pins announce themselves', (tester) async {
    final handle = tester.ensureSemantics();
    imageStore.images[MapType.lab] = _fakeDiagram();

    await pumpTab(
      tester,
      pins: [
        _pin('a', name: 'Battery cart', x: 0.2, y: 0.3, inventoryItemId: 'i1'),
        _pin('b', name: 'Charging station', x: 0.7, y: 0.6),
      ],
    );

    expect(
      find.bySemanticsLabel('Lab diagram, 2 locations marked'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Battery cart, linked to a tool'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Charging station, not linked to a tool'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('an empty diagram says nothing is marked', (tester) async {
    final handle = tester.ensureSemantics();
    imageStore.images[MapType.lab] = _fakeDiagram();

    await pumpTab(tester, pins: const []);

    expect(
      find.bySemanticsLabel('Lab diagram, no locations marked'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('tapping a pin shows its linked tool and locations', (
    tester,
  ) async {
    imageStore.images[MapType.lab] = _fakeDiagram();

    await pumpTab(
      tester,
      pins: [_pin('a', name: 'Battery cart', inventoryItemId: 'inv-1')],
      items: [
        _item('inv-1', name: 'Cordless Drill', lab: 'RC1-DB', pit: 'CAB-A2'),
      ],
    );

    await tester.tap(find.byIcon(Icons.location_on));
    await tester.pumpAndSettle();

    expect(find.text('Battery cart'), findsOneWidget);
    expect(find.text('Cordless Drill'), findsOneWidget);
    expect(find.text('RC1-DB'), findsOneWidget);
    expect(find.text('CAB-A2'), findsOneWidget);
  });

  testWidgets('a pin with no linked tool says so in the detail sheet', (
    tester,
  ) async {
    imageStore.images[MapType.lab] = _fakeDiagram();

    await pumpTab(tester, pins: [_pin('a', name: 'Empty shelf')]);

    await tester.tap(find.byIcon(Icons.location_on_outlined));
    await tester.pumpAndSettle();

    expect(find.text('No tool linked to this pin.'), findsOneWidget);
  });

  testWidgets('adding a pin with a failed sync write surfaces a SnackBar', (
    tester,
  ) async {
    imageStore.images[MapType.lab] = _fakeDiagram();
    await pumpTab(tester);
    mapSync.failWith = Exception('offline');

    await tester.tap(find.text('Add pin'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Battery cart',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add pin').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not save "Battery cart"'),
      findsOneWidget,
    );
  });

  testWidgets('dragging a pin writes the new position to the controller', (
    tester,
  ) async {
    imageStore.images[MapType.lab] = _fakeDiagram();

    await pumpTab(
      tester,
      pins: [_pin('a', name: 'Battery cart', x: 0.5, y: 0.5)],
    );

    final pinFinder = find.byIcon(Icons.location_on_outlined);
    await tester.drag(pinFinder, const Offset(50, 0));
    await tester.pumpAndSettle();

    expect(mapSync.upserts, isNotEmpty);
    final saved = mapSync.upserts.last;
    expect(saved.id, 'a');
    expect(saved.x, greaterThan(0.5));
    expect(saved.y, closeTo(0.5, 0.001));
  });

  testWidgets('a set diagram offers change and remove actions', (tester) async {
    imageStore.images[MapType.lab] = _fakeDiagram();
    await pumpTab(tester);

    await tester.tap(find.byTooltip('Diagram options'));
    await tester.pumpAndSettle();

    expect(find.text('Change diagram'), findsOneWidget);
    expect(find.text('Remove diagram'), findsOneWidget);
  });

  testWidgets('removing the diagram drops back to the empty state', (
    tester,
  ) async {
    imageStore.images[MapType.lab] = _fakeDiagram();
    await pumpTab(tester);

    await tester.tap(find.byTooltip('Diagram options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove diagram'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(imageStore.images[MapType.lab], isNull);
    expect(find.text('No lab diagram set'), findsOneWidget);
    expect(find.text('Choose diagram'), findsOneWidget);
  });

  testWidgets('a failed removal keeps the diagram and says why', (
    tester,
  ) async {
    imageStore.images[MapType.lab] = _fakeDiagram();
    imageStore.clearFailure = Exception('offline');
    await pumpTab(tester);

    await tester.tap(find.byTooltip('Diagram options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove diagram'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not remove the diagram'), findsOneWidget);
    expect(find.text('No lab diagram set'), findsNothing);
  });

  testWidgets('the diagram options menu stays closed while a removal is in '
      'flight', (tester) async {
    imageStore.images[MapType.lab] = _fakeDiagram();
    final gate = Completer<void>();
    imageStore.clearGate = gate.future;
    await pumpTab(tester);

    await tester.tap(find.byTooltip('Diagram options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove diagram'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump();

    await tester.tap(find.byTooltip('Diagram options'));
    await tester.pumpAndSettle();
    expect(find.text('Remove diagram'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('No lab diagram set'), findsOneWidget);
  });

  testWidgets('switching map type while a removal is in flight leaves the new '
      'map untouched', (tester) async {
    imageStore.images[MapType.lab] = _fakeDiagram();
    imageStore.images[MapType.pit] = _fakeDiagram();
    final gate = Completer<void>();
    imageStore.clearGate = gate.future;
    await pumpTab(tester);

    await tester.tap(find.byTooltip('Diagram options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove diagram'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump();

    await tester.tap(find.text('Pit'));
    await tester.pumpAndSettle();
    expect(find.text('No pit diagram set'), findsNothing);

    expect(imageStore.images[MapType.lab], isNotNull);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('No pit diagram set'), findsNothing);

    expect(imageStore.images[MapType.lab], isNull);
    expect(imageStore.images[MapType.pit], isNotNull);
  });

  testWidgets('switching to the vehicle map shows its diagram without '
      'touching the lab one', (tester) async {
    imageStore.images[MapType.lab] = _fakeDiagram();
    imageStore.nextPick = _fakeDiagram();
    await pumpTab(tester);

    await tester.tap(find.text('Vehicle'));
    await tester.pumpAndSettle();
    expect(find.text('No vehicle diagram set'), findsOneWidget);

    await tester.tap(find.text('Choose diagram'));
    await tester.pumpAndSettle();

    expect(find.text('No vehicle diagram set'), findsNothing);

    expect(imageStore.images[MapType.vehicle], isNotNull);
    expect(imageStore.images[MapType.lab], isNotNull);
  });
}
