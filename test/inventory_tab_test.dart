import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/inventory_tab.dart';

import 'support/fake_inventory_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

const _signedInUser = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

InventoryItem _item(
  String id, {
  required String name,
  String lab = '',
  String pit = '',
  InventoryStatus status = InventoryStatus.inLab,
}) => InventoryItem(
  id: id,
  name: name,
  labLocation: lab,
  pitLocation: pit,
  status: status,
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeInventorySyncService sync;
  late InventoryController controller;

  setUp(() {
    sync = FakeInventorySyncService();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // Builds a signed-in, bootstrapped controller and (optionally) seeds it via a
  // realtime emission, then pumps the tab under the app theme on a tall surface
  // so the list builds every row.
  Future<void> pumpTab(WidgetTester tester, List<InventoryItem> seed) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    controller = InventoryController(
      authService: FakeSpectrumAuthService(initialUser: _signedInUser),
      syncService: sync,
    );
    // Cleanup runs only when initialization reached the assignment.
    addTearDown(controller.dispose);
    await controller.bootstrap();
    if (seed.isNotEmpty) sync.emit(seed);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        home: Scaffold(body: InventoryTab(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a row per item with name and both location codes', (
    tester,
  ) async {
    await pumpTab(tester, [
      _item('a', name: 'Cordless Drill', lab: 'RC1-DB', pit: 'CAB-A2'),
      _item(
        'b',
        name: 'Crimper',
        lab: 'RC2-TB',
        pit: 'CAB-B3',
        status: InventoryStatus.inPit,
      ),
    ]);

    expect(find.text('Cordless Drill'), findsOneWidget);
    expect(find.text('Crimper'), findsOneWidget);
    // Codes render in mono, uppercase (The Stencil Rule).
    expect(find.text('RC1-DB'), findsOneWidget);
    expect(find.text('CAB-A2'), findsOneWidget);
    // Status renders as a labelled tag, never color alone.
    expect(find.text('In Lab'), findsOneWidget);
    expect(find.text('In Pit'), findsOneWidget);
  });

  testWidgets('empty locations render a dash placeholder', (tester) async {
    await pumpTab(tester, [_item('a', name: 'Loose Bolt')]);
    expect(find.text('--'), findsNWidgets(2)); // both lab and pit empty
  });

  testWidgets('search filters by name', (tester) async {
    await pumpTab(tester, [
      _item('a', name: 'Cordless Drill', lab: 'RC1-DB'),
      _item('b', name: 'Crimper', lab: 'RC2-TB'),
    ]);

    await tester.enterText(find.byType(TextField).first, 'crimp');
    await tester.pumpAndSettle();

    expect(find.text('Crimper'), findsOneWidget);
    expect(find.text('Cordless Drill'), findsNothing);
  });

  testWidgets('search filters by location', (tester) async {
    await pumpTab(tester, [
      _item('a', name: 'Cordless Drill', lab: 'RC1-DB', pit: 'CAB-A2'),
      _item('b', name: 'Crimper', lab: 'RC2-TB', pit: 'CAB-B3'),
    ]);

    await tester.enterText(find.byType(TextField).first, 'cab-a2');
    await tester.pumpAndSettle();

    expect(find.text('Cordless Drill'), findsOneWidget);
    expect(find.text('Crimper'), findsNothing);
  });

  testWidgets('empty board shows the drawn slot and an add affordance', (
    tester,
  ) async {
    await pumpTab(tester, const <InventoryItem>[]);

    expect(find.text('The board is empty'), findsOneWidget);
    // Only the empty-state button (the FAB is hidden while the board is empty).
    expect(find.text('Add tool'), findsOneWidget);
  });

  testWidgets('tapping the status tag advances the status via upsert', (
    tester,
  ) async {
    await pumpTab(tester, [_item('a', name: 'Cordless Drill')]);

    await tester.tap(find.text('In Lab'));
    await tester.pumpAndSettle();

    // inLab -> inPit, written optimistically and recorded on the sync service.
    expect(controller.items.single.status, InventoryStatus.inPit);
    expect(sync.upserts.last.id, 'a');
    expect(sync.upserts.last.status, InventoryStatus.inPit);
  });

  testWidgets('a failed sync write surfaces an error via SnackBar', (
    tester,
  ) async {
    await pumpTab(tester, [_item('a', name: 'Cordless Drill')]);
    sync.failWith = Exception('offline');

    await tester.tap(find.text('In Lab'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not update "Cordless Drill"'),
      findsOneWidget,
    );
  });

  testWidgets('add sheet saves a new item with the entered values', (
    tester,
  ) async {
    await pumpTab(tester, const <InventoryItem>[]);

    await tester.tap(find.text('Add tool'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Wrench');
    await tester.enterText(
      find.widgetWithText(TextField, 'Lab location'),
      'RC3',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Pit location'),
      'CAB-C1',
    );
    await tester.pumpAndSettle();

    // Two 'Add tool' labels now exist (the empty board button behind the sheet
    // and the sheet's save button); the sheet is last in the overlay.
    await tester.tap(find.text('Add tool').last);
    await tester.pumpAndSettle();

    expect(sync.upserts, hasLength(1));
    final saved = sync.upserts.single;
    expect(saved.name, 'Wrench');
    expect(saved.labLocation, 'RC3');
    expect(saved.pitLocation, 'CAB-C1');
    expect(saved.status, InventoryStatus.inLab);
    // New records get a UUID v4, never a timestamp-derived id (#161). Matched on
    // shape rather than merely non-empty, which 'new-item' would also satisfy
    // (#169).
    expect(saved.id, isNot(startsWith('inv_')));
    expect(
      saved.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ),
      ),
    );
  });
}
