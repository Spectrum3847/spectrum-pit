import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/item_jump_dialog.dart';

import 'support/fake_inventory_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

const _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

InventoryItem _item(String id, String name, String lab, String pit) =>
    InventoryItem(
      id: id,
      name: name,
      labLocation: lab,
      pitLocation: pit,
      status: InventoryStatus.inPit,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<InventoryController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final sync = FakeInventorySyncService();
  final controller = InventoryController(
    authService: FakeSpectrumAuthService(initialUser: _user),
    syncService: sync,
  );
  addTearDown(controller.dispose);
  await controller.bootstrap();
  sync.emit([
    _item('a', 'Cordless Drill', 'RC1-DB', 'CAB-A2'),
    _item('b', 'Crimper', 'RC2-TB', 'CAB-B3'),
  ]);
  return controller;
}

class _Result {
  InventoryItem? picked;
  bool done = false;
}

Future<_Result> _open(WidgetTester tester) async {
  final controller = await _controller();
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkAppTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result.picked = await showItemJump(context, controller: controller);
            result.done = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('lists items with both location codes and status', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('RC1-DB'), findsOneWidget);
    expect(find.text('CAB-A2'), findsOneWidget);
    expect(find.textContaining('In Pit'), findsNWidgets(2));
  });

  testWidgets('filters by name and location, case-insensitive', (tester) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField), 'CRIMP');
    await tester.pumpAndSettle();
    expect(find.textContaining('Crimper'), findsOneWidget);
    expect(find.textContaining('Cordless Drill'), findsNothing);

    await tester.enterText(find.byType(TextField), 'cab-a2');
    await tester.pumpAndSettle();
    expect(find.textContaining('Cordless Drill'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching tools'), findsOneWidget);
  });

  testWidgets('Enter picks the first match', (tester) async {
    final result = await _open(tester);
    await tester.enterText(find.byType(TextField), 'rc');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(result.picked?.id, 'a');
  });

  testWidgets('tapping a row pops with that item', (tester) async {
    final result = await _open(tester);
    await tester.tap(find.textContaining('Crimper'));
    await tester.pumpAndSettle();
    expect(result.picked?.id, 'b');
  });

  testWidgets('Cancel pops null', (tester) async {
    final result = await _open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result.done, isTrue);
    expect(result.picked, isNull);
  });

  group('ItemJumpShortcut', () {
    Future<int> press(WidgetTester tester, {required bool typing}) async {
      var jumps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ItemJumpShortcut(
              enabled: true,
              onJump: (_) => jumps++,
              child: typing
                  ? const TextField(autofocus: true)
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      return jumps;
    }

    testWidgets('slash jumps when not typing', (tester) async {
      expect(await press(tester, typing: false), 1);
    });

    testWidgets('slash is left alone while typing', (tester) async {
      expect(await press(tester, typing: true), 0);
    });
  });
}
