import '../models/driver_schedule.dart';
import '../models/pit_shift.dart';

class DriverScheduleImport {
  const DriverScheduleImport._();

  static List<PitShift> toShifts({
    required DriverSchedule schedule,
    required String competition,
    required Map<String, String> uidByName,
    required String idPrefix,
    required DateTime now,
  }) {
    final byLowerName = {
      for (final entry in uidByName.entries)
        entry.key.trim().toLowerCase(): entry.value,
    };
    final groups = schedule.config.effectiveRenderGroups;
    final shifts = <PitShift>[];

    for (var slot = 0; slot < schedule.slots; slot++) {
      final match = slot + 1;
      for (var g = 0; g < groups.length; g++) {
        final group = groups[g];

        final names = <String>[];
        for (final roleKey in group.roleKeys) {
          final name = schedule.nameAt(roleKey, slot).trim();
          if (name.isNotEmpty && !names.contains(name)) {
            names.add(name);
          }
        }
        if (names.isEmpty) {
          continue;
        }
        shifts.add(
          PitShift(
            id: '$idPrefix-$match-$g',
            label: labelFor(group.label, match),
            kind: ShiftKind.matchBlock,
            competition: competition,
            assignedUids: [
              for (final name in names)
                byLowerName[name.toLowerCase()] ?? PitShift.unlinkedUid(name),
            ],
            assignedNames: names,
            startMatch: match,
            endMatch: match,
            importedFrom: PitShift.driverScheduleImport,
            updatedAt: now,
          ),
        );
      }
    }
    return shifts;
  }

  static String labelFor(String? groupLabel, int match) =>
      groupLabel == null || groupLabel.isEmpty
      ? 'Drive team, match $match'
      : '$groupLabel drive team, match $match';

  static List<PitShift> previousImports(
    Iterable<PitShift> shifts,
    String competition,
  ) => [
    for (final shift in shifts)
      if (shift.competition == competition &&
          shift.importedFrom == PitShift.driverScheduleImport)
        shift,
  ];

  static Future<void> commit({
    required List<PitShift> shifts,
    required List<PitShift> previous,
    required bool replace,
    required Future<void> Function(PitShift shift) upsert,
    required Future<void> Function(String id) delete,
  }) async {
    final written = <String>[];
    try {
      for (final shift in shifts) {
        await upsert(shift);
        written.add(shift.id);
      }
    } catch (_) {
      for (final id in written) {
        try {
          await delete(id);
        } catch (_) {}
      }
      rethrow;
    }
    if (!replace) return;
    for (final stale in previous) {
      await delete(stale.id);
    }
  }

  static String summaryOf(
    List<PitShift> shifts, {
    required String competition,
    required bool replace,
  }) {
    final count = '${shifts.length} shift${shifts.length == 1 ? '' : 's'}';
    final unlinked = shifts.where((s) => s.hasUnlinkedAssignees).length;
    final note = unlinked == 0
        ? ''
        : ' $unlinked ${unlinked == 1 ? 'has' : 'have'} someone with no'
              ' account.';
    return replace
        ? 'Replaced the previous import with $count.$note'
        : 'Added $count to $competition.$note';
  }
}
