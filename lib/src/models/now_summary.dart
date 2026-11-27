import 'borrow_record.dart';
import 'inventory_item.dart';
import 'packing_record.dart';
import 'pit_shift.dart';

const int _maxMyShifts = 3;

class NowSummary {
  const NowSummary({
    required this.overdueLoans,
    required this.openLoanCount,
    required this.myShifts,
    required this.shiftConflictCount,
    required this.packingCounts,
    required this.packingTotal,
  });

  factory NowSummary.from({
    required List<InventoryItem> items,
    required List<PackingRecord> packing,
    required List<BorrowRecord> loans,
    required List<PitShift> shifts,
    required String? currentUid,
    required DateTime now,
  }) {
    final open = loans.where((loan) => !loan.returned).toList();
    final overdue = open.where((loan) => loan.isOverdueAt(now)).toList()
      ..sort((a, b) => a.estimatedReturn!.compareTo(b.estimatedReturn!));

    final mine = currentUid == null
        ? const <PitShift>[]
        : shifts.where((s) => s.assignedUids.contains(currentUid)).toList();
    final notEnded = mine
        .where((s) => !(s.endsAt != null && s.endsAt!.isBefore(now)))
        .toList();
    final upcoming =
        notEnded.where((s) => s.kind != ShiftKind.unavailable).toList()
          ..sort(_byStart);

    final recordByItem = {for (final r in packing) r.itemId: r};
    final counts = {for (final s in PackingStatus.values) s: 0};
    for (final item in items) {
      final status =
          recordByItem[item.id]?.packingStatus ?? PackingStatus.notStarted;
      counts[status] = counts[status]! + 1;
    }

    return NowSummary(
      overdueLoans: overdue,
      openLoanCount: open.length,
      myShifts: upcoming.take(_maxMyShifts).toList(),
      shiftConflictCount: findPitShiftConflicts(notEnded).length,
      packingCounts: counts,
      packingTotal: items.length,
    );
  }

  final List<BorrowRecord> overdueLoans;
  final int openLoanCount;
  final List<PitShift> myShifts;

  final int shiftConflictCount;

  final Map<PackingStatus, int> packingCounts;
  final int packingTotal;

  int get readyCount => packingCounts[PackingStatus.ready] ?? 0;

  bool get needsAttention => overdueLoans.isNotEmpty || shiftConflictCount > 0;
}

int _byStart(PitShift a, PitShift b) {
  final byTime = _nullsLast(a.startsAt, b.startsAt);
  if (byTime != 0) return byTime;
  final byMatch = _nullsLast(a.startMatch, b.startMatch);
  if (byMatch != 0) return byMatch;
  return a.label.compareTo(b.label);
}

int _nullsLast<T extends Comparable<Object>>(T? a, T? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
