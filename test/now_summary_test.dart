import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/borrow_record.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';
import 'package:spectrumpit/src/models/now_summary.dart';
import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';

final _now = DateTime.utc(2026, 4, 10, 12);

BorrowRecord _loan(String id, {DateTime? due, bool returned = false}) =>
    BorrowRecord(
      id: id,
      toolName: 'Tool $id',
      teamName: 'Team',
      teamNumber: 254,
      competition: 'Houston',
      checkedOutAt: DateTime.utc(2026, 4, 1),
      estimatedReturn: due,
      returned: returned,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

PitShift _shift(
  String id, {
  String label = 'Shift',
  ShiftKind kind = ShiftKind.pitDuty,
  List<String> uids = const ['me'],
  int? startMatch,
  int? endMatch,
  DateTime? startsAt,
  DateTime? endsAt,
}) => PitShift(
  id: id,
  label: label,
  kind: kind,
  competition: 'Houston',
  assignedUids: uids,
  assignedNames: const ['Me'],
  startMatch: startMatch,
  endMatch: endMatch,
  startsAt: startsAt,
  endsAt: endsAt,
  updatedAt: DateTime.utc(2026, 1, 1),
);

InventoryItem _item(String id) => InventoryItem(
  id: id,
  name: id,
  labLocation: '',
  pitLocation: '',
  status: InventoryStatus.inLab,
  updatedAt: DateTime.utc(2026, 1, 1),
);

PackingRecord _pack(String itemId, PackingStatus status) => PackingRecord(
  id: 'p-$itemId',
  itemId: itemId,
  packingStatus: status,
  updatedAt: DateTime.utc(2026, 1, 1),
);

NowSummary _build({
  List<InventoryItem> items = const [],
  List<PackingRecord> packing = const [],
  List<BorrowRecord> loans = const [],
  List<PitShift> shifts = const [],
  String? uid = 'me',
}) => NowSummary.from(
  items: items,
  packing: packing,
  loans: loans,
  shifts: shifts,
  currentUid: uid,
  now: _now,
);

void main() {
  test('overdue loans are open and past due, oldest due first', () {
    final s = _build(
      loans: [
        _loan('new', due: _now.subtract(const Duration(hours: 1))),
        _loan('old', due: _now.subtract(const Duration(days: 2))),
        _loan('future', due: _now.add(const Duration(days: 1))),
        _loan('nodue'),
        _loan(
          'back',
          due: _now.subtract(const Duration(days: 9)),
          returned: true,
        ),
      ],
    );
    expect(s.overdueLoans.map((l) => l.id), ['old', 'new']);
    expect(s.openLoanCount, 4);
    expect(s.needsAttention, isTrue);
  });

  test('my shifts: mine only, no unavailable, sorted, capped at 3', () {
    final s = _build(
      shifts: [
        _shift('other', uids: ['you'], startMatch: 1),
        _shift('off', kind: ShiftKind.unavailable, startMatch: 1),
        _shift('m20', label: 'B', startMatch: 20, endMatch: 30),
        _shift('m10b', label: 'B', startMatch: 10, endMatch: 12),
        _shift('m10a', label: 'A', startMatch: 10, endMatch: 12),
        _shift('timed', startsAt: _now.add(const Duration(hours: 1))),
        _shift('none', label: 'Z'),
      ],
    );
    expect(s.myShifts.map((x) => x.id), ['timed', 'm10a', 'm10b']);
  });

  test('ended shifts are dropped, shifts with no times stay', () {
    final s = _build(
      shifts: [
        _shift(
          'done',
          startsAt: _now.subtract(const Duration(hours: 3)),
          endsAt: _now.subtract(const Duration(hours: 1)),
        ),
        _shift(
          'running',
          label: 'A',
          endsAt: _now.add(const Duration(hours: 1)),
        ),
        _shift('untimed', label: 'B'),
      ],
    );
    expect(s.myShifts.map((x) => x.id), ['running', 'untimed']);
  });

  test('no signed-in user has no shifts or conflicts', () {
    final s = _build(
      uid: null,
      shifts: [
        _shift('a', startMatch: 1, endMatch: 5),
        _shift('b', startMatch: 3, endMatch: 8),
      ],
    );
    expect(s.myShifts, isEmpty);
    expect(s.shiftConflictCount, 0);
  });

  test('conflict count covers only pairs involving the current user', () {
    final s = _build(
      shifts: [
        _shift('a', startMatch: 1, endMatch: 5),
        _shift('b', startMatch: 3, endMatch: 8),
        _shift('c', uids: ['you'], startMatch: 1, endMatch: 5),
        _shift('d', uids: ['you'], startMatch: 2, endMatch: 6),
      ],
    );
    expect(s.shiftConflictCount, 1);
    expect(s.needsAttention, isTrue);
  });

  test('shifts that already ended raise no conflict', () {
    final s = _build(
      shifts: [
        _shift(
          'old-a',
          startsAt: _now.subtract(const Duration(hours: 5)),
          endsAt: _now.subtract(const Duration(hours: 3)),
        ),
        _shift(
          'old-b',
          startsAt: _now.subtract(const Duration(hours: 4)),
          endsAt: _now.subtract(const Duration(hours: 2)),
        ),
      ],
    );
    expect(s.shiftConflictCount, 0);
    expect(s.needsAttention, isFalse);
  });

  test('packing counts treat a missing record as not started', () {
    final s = _build(
      items: [_item('a'), _item('b'), _item('c'), _item('d')],
      packing: [
        _pack('a', PackingStatus.ready),
        _pack('b', PackingStatus.staging),
        _pack('orphan', PackingStatus.ready),
      ],
    );
    expect(s.packingTotal, 4);
    expect(s.readyCount, 1);
    expect(s.packingCounts[PackingStatus.staging], 1);
    expect(s.packingCounts[PackingStatus.notStarted], 2);
    expect(s.needsAttention, isFalse);
  });
}
