import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/borrow_controller.dart';
import 'package:spectrumpit/src/state/inventory_controller.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/state/pit_shift_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/now_tab.dart';

import 'support/fake_borrow_sync_service.dart';
import 'support/fake_inventory_sync_service.dart';
import 'support/fake_packing_sync_service.dart';
import 'support/fake_pit_shift_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

const _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

class _Rig {
  late final InventoryController inventory;
  late final PackingController packing;
  late final BorrowController borrow;
  late final PitShiftController shifts;
  final inventorySync = FakeInventorySyncService();
  final packingSync = FakePackingSyncService();
  final borrowSync = FakeBorrowSyncService();
  final shiftSync = FakePitShiftSyncService();

  Future<void> init({
    List<InventoryItem> items = const [],
    List<PackingRecord> records = const [],
    List<BorrowRecord> loans = const [],
    List<PitShift> shiftList = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final auth = FakeSpectrumAuthService(initialUser: _user);
    inventory = InventoryController(
      authService: auth,
      syncService: inventorySync,
    );
    packing = PackingController(authService: auth, syncService: packingSync);
    borrow = BorrowController(authService: auth, syncService: borrowSync);
    shifts = PitShiftController(authService: auth, syncService: shiftSync);
    for (final c in [inventory, packing, borrow, shifts]) {
      addTearDown(c.dispose);
    }
    await Future.wait([
      inventory.bootstrap(),
      packing.bootstrap(),
      borrow.bootstrap(),
      shifts.bootstrap(),
    ]);
    if (items.isNotEmpty) inventorySync.emit(items);
    if (records.isNotEmpty) packingSync.emit(records);
    if (loans.isNotEmpty) borrowSync.emit(loans);
    if (shiftList.isNotEmpty) shiftSync.emit(shiftList);
  }

  Widget tab({
    List<String> taps = const [],
    void Function(String)? onTap,
    bool jump = true,
  }) => NowTab(
    inventoryController: inventory,
    packingController: packing,
    borrowController: borrow,
    pitShiftController: shifts,
    currentUid: 'uid-1',
    onOpenBorrowed: () => onTap?.call('borrowed'),
    onOpenPacking: () => onTap?.call('packing'),
    onOpenSchedule: () => onTap?.call('schedule'),
    onJump: jump ? () => onTap?.call('jump') : null,
  );
}

InventoryItem _item(String id) => InventoryItem(
  id: id,
  name: 'Item $id',
  labLocation: 'RC1',
  pitLocation: 'CAB',
  status: InventoryStatus.inLab,
  updatedAt: DateTime.utc(2026, 1, 1),
);

BorrowRecord _loan(String id, {DateTime? due}) => BorrowRecord(
  id: id,
  toolName: 'Torque Wrench',
  teamName: 'Cheesy Poofs',
  teamNumber: 254,
  competition: 'Houston',
  checkedOutAt: DateTime.utc(2026, 1, 1),
  estimatedReturn: due,
  returned: false,
  updatedAt: DateTime.utc(2026, 1, 1),
);

PitShift _shift(String id, {int start = 12, int end = 20}) => PitShift(
  id: id,
  label: 'Pit duty',
  kind: ShiftKind.pitDuty,
  competition: 'Houston',
  assignedUids: const ['uid-1'],
  assignedNames: const ['Tester'],
  startMatch: start,
  endMatch: end,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Widget _app(Widget body, {TextScaler? scaler}) => MaterialApp(
  theme: buildDarkAppTheme(),
  builder: scaler == null
      ? null
      : (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        ),
  home: Scaffold(body: body),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'quiet when nothing needs attention, empty shifts offer Schedule',
    (tester) async {
      final rig = _Rig();
      await rig.init();
      final taps = <String>[];
      await tester.pumpWidget(_app(rig.tab(onTap: taps.add)));

      expect(find.text('Nothing needs attention'), findsOneWidget);
      expect(find.text('No upcoming shifts assigned to you'), findsOneWidget);
      await tester.tap(find.text('Open Schedule'));
      expect(taps, ['schedule']);
    },
  );

  testWidgets('overdue loan shows tool, team, lateness and opens Borrowed', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.init(
      loans: [
        _loan('l1', due: DateTime.now().subtract(const Duration(days: 2))),
      ],
    );
    final taps = <String>[];
    await tester.pumpWidget(_app(rig.tab(onTap: taps.add)));

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('Torque Wrench'), findsOneWidget);
    expect(find.textContaining('254 Cheesy Poofs'), findsOneWidget);
    expect(find.textContaining('2d late'), findsOneWidget);
    expect(find.text('Nothing needs attention'), findsNothing);
    await tester.tap(find.textContaining('Torque Wrench'));
    expect(taps, ['borrowed']);
  });

  testWidgets('shows next shift range, packing counts and loan count', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.init(
      items: [_item('a'), _item('b')],
      records: [
        PackingRecord(
          id: 'p',
          itemId: 'a',
          packingStatus: PackingStatus.ready,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
      loans: [_loan('l1')],
      shiftList: [_shift('s1')],
    );
    final taps = <String>[];
    await tester.pumpWidget(_app(rig.tab(onTap: taps.add)));

    expect(
      find.textContaining('Matches 12-20', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('1 of 2 ready'), findsOneWidget);
    expect(
      find.textContaining('Not started 1', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Ready 1', findRichText: true), findsOneWidget);
    expect(find.text('1 tool out on loan'), findsOneWidget);

    await tester.tap(find.text('1 of 2 ready'));
    await tester.tap(find.text('1 tool out on loan'));
    expect(taps, ['packing', 'borrowed']);
  });

  testWidgets('Find a tool calls onJump and is omitted without it', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.init();
    final taps = <String>[];
    await tester.pumpWidget(_app(rig.tab(onTap: taps.add)));
    await tester.tap(find.text('Find a tool'));
    expect(taps, ['jump']);

    await tester.pumpWidget(_app(rig.tab(jump: false)));
    expect(find.text('Find a tool'), findsNothing);
  });

  testWidgets('survives 200% text on a 360x640 phone', (tester) async {
    final rig = _Rig();
    await rig.init(
      items: [_item('a'), _item('b')],
      loans: [
        _loan('l1', due: DateTime.now().subtract(const Duration(hours: 5))),
        _loan('l2', due: DateTime.now().subtract(const Duration(days: 1))),
      ],
      shiftList: [_shift('s1'), _shift('s2', start: 30, end: 40)],
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(rig.tab(), scaler: const TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
