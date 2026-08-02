import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/ui/borrow_tab.dart';

import 'support/fake_borrow_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

const _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

BorrowRecord _record(
  String id, {
  String toolName = 'Drill',
  String teamName = 'Cheesy Poofs',
  int teamNumber = 254,
  bool returned = false,
  DateTime? estimatedReturn,
}) => BorrowRecord(
  id: id,
  toolName: toolName,
  teamName: teamName,
  teamNumber: teamNumber,
  competition: 'Texas States',
  checkedOutAt: DateTime.utc(2026, 3, 1, 10),
  estimatedReturn: estimatedReturn,
  returned: returned,
  updatedAt: DateTime.utc(2026, 3, 1, 10),
);

Future<BorrowController> _makeController({
  List<BorrowRecord> initial = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sync = FakeBorrowSyncService();
  final controller = BorrowController(
    authService: FakeSpectrumAuthService(initialUser: _user),
    syncService: sync,
  );
  await controller.bootstrap();
  if (initial.isNotEmpty) sync.emit(initial);
  return controller;
}

Widget _wrap(BorrowController controller) => MaterialApp(
  home: Scaffold(body: BorrowTab(controller: controller)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state shows the dashed board and check out button', (
    tester,
  ) async {
    final controller = await _makeController();
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('No tools on loan'), findsOneWidget);
    expect(find.text('Check out tool'), findsWidgets);
    controller.dispose();
  });

  testWidgets('items are displayed with tool name and team', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', toolName: 'Drill', teamNumber: 254)],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('Drill'), findsOneWidget);
    expect(find.text('254'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('active loan shows Check in button', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', returned: false)],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('Check in'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('returned loan shows Returned chip', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', returned: true)],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('Returned'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    controller.dispose();
  });

  testWidgets('tapping Check in marks the record as returned', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', returned: false)],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();

    expect(controller.items.single.returned, isTrue);
    expect(controller.items.single.checkedInAt, isNotNull);
    controller.dispose();
  });

  testWidgets('FAB opens the checkout editor', (tester) async {
    final controller = await _makeController();
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Check out tool'), findsWidgets);
    // Should have text fields for tool name, team name, team number, competition
    expect(find.byType(TextField), findsNWidgets(4));
    controller.dispose();
  });

  testWidgets('checkout editor creates a new record', (tester) async {
    final controller = await _makeController();
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Fill in the form
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Wrench');
    await tester.enterText(fields.at(1), 'The Cheesy Poofs');
    await tester.enterText(fields.at(2), '254');
    await tester.enterText(fields.at(3), 'Texas States');

    await tester.tap(find.widgetWithText(FilledButton, 'Check out'));
    await tester.pumpAndSettle();

    expect(controller.items.length, 1);
    expect(controller.items.single.toolName, 'Wrench');
    expect(controller.items.single.teamNumber, 254);
    controller.dispose();
  });

  testWidgets('tapping a row opens the edit editor', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', toolName: 'Drill')],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drill'));
    await tester.pumpAndSettle();

    expect(find.text('Edit loan'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    controller.dispose();
  });

  testWidgets('delete button removes the record', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', toolName: 'Drill')],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drill'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    // Confirm dialog
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(controller.items, isEmpty);
    controller.dispose();
  });

  testWidgets('overdue loan shows Overdue chip', (tester) async {
    final controller = await _makeController(
      initial: [
        _record(
          'a',
          toolName: 'Drill',
          returned: false,
          estimatedReturn: DateTime.utc(2026, 1, 1), // already past
        ),
      ],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('active loans sort above returned ones', (tester) async {
    final controller = await _makeController(
      initial: [
        _record('returned-1', toolName: 'Returned Tool', returned: true),
        _record('active-1', toolName: 'Active Tool', returned: false),
      ],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    // The list should show active first, then returned
    final activeFinder = find.text('Active Tool');
    final returnedFinder = find.text('Returned Tool');
    expect(activeFinder, findsOneWidget);
    expect(returnedFinder, findsOneWidget);

    // Active should appear before returned in the widget tree
    final activeBox = tester.getCenter(activeFinder);
    final returnedBox = tester.getCenter(returnedFinder);
    expect(activeBox.dy, lessThan(returnedBox.dy));
    controller.dispose();
  });
}
