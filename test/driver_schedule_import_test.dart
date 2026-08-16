import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/models/driver_schedule.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';
import 'package:spectrumpit/src/services/driver_schedule_generator.dart';
import 'package:spectrumpit/src/services/driver_schedule_import.dart';

void main() {
  final now = DateTime.utc(2026, 8, 14, 12);

  group('shape', () {
    test('one shift per match on a single-robot rotation', () {
      final shifts = _import(_schedule(singleRobotConfig, slots: 5));

      expect(shifts, hasLength(5));
      expect(shifts.first.kind, ShiftKind.matchBlock);
      expect(shifts.first.startMatch, 1);
      expect(shifts.first.endMatch, 1);
      expect(shifts.last.startMatch, 5);
    });

    test('one shift per robot per match on a two-robot rotation', () {
      final shifts = _import(_schedule(twoRobotConfig, slots: 4));

      expect(shifts, hasLength(8));
      expect(
        shifts.where((s) => s.startMatch == 1).map((s) => s.label),
        containsAll([
          'Robot 1 drive team, match 1',
          'Robot 2 drive team, match 1',
        ]),
      );
    });

    test('a single-robot label does not name a robot', () {
      final shifts = _import(_schedule(singleRobotConfig, slots: 1));

      expect(shifts.single.label, 'Drive team, match 1');
    });

    test('everyone on the robot that match is on the shift, once', () {
      final schedule = _schedule(singleRobotConfig, slots: 1);
      final shifts = _import(schedule);

      final expected = schedule.namesInSlot(0);
      expect(shifts.single.assignedNames.toSet(), expected);
      expect(
        shifts.single.assignedNames.length,
        shifts.single.assignedNames.toSet().length,
        reason: 'one person in two roles is on the shift once',
      );
    });

    test('assignedUids and assignedNames stay index aligned', () {
      final shifts = _import(_schedule(singleRobotConfig, slots: 3));

      for (final shift in shifts) {
        expect(shift.assignedUids, hasLength(shift.assignedNames.length));
      }
    });

    test('every shift is tagged as imported', () {
      final shifts = _import(_schedule(singleRobotConfig, slots: 2));

      expect(
        shifts.every((s) => s.importedFrom == PitShift.driverScheduleImport),
        isTrue,
      );
      expect(shifts.every((s) => s.isImported), isTrue);
    });

    test('a rotation nobody is in imports as nothing', () {
      final empty = DriverScheduleGenerator(
        random: Random(7),
      ).generate(singleRobotConfig, const {}, slots: 4, handoff: false);

      expect(_import(empty), isEmpty);
    });

    test('two imports of the same rotation do not collide on id', () {
      final schedule = _schedule(singleRobotConfig, slots: 3);
      final first = _import(schedule, idPrefix: 'drv-1');
      final second = _import(schedule, idPrefix: 'drv-2');

      final ids = {...first.map((s) => s.id), ...second.map((s) => s.id)};
      expect(ids, hasLength(first.length + second.length));
    });
  });

  group('people with no account', () {
    test('a known name keeps its real uid', () {
      final schedule = _schedule(singleRobotConfig, slots: 1);
      final known = schedule.namesInSlot(0).first;
      final shifts = _import(schedule, uidByName: {known: 'uid-known'});

      final index = shifts.single.assignedNames.indexOf(known);
      expect(index, isNot(-1));
      expect(shifts.single.assignedUids[index], 'uid-known');
    });

    test('an unknown name is imported with a stand-in uid, not refused', () {
      final shifts = _import(_schedule(singleRobotConfig, slots: 1));

      expect(shifts.single.assignedNames, isNotEmpty);
      expect(
        shifts.single.assignedUids.every(
          (uid) => uid.startsWith(PitShift.unlinkedUidPrefix),
        ),
        isTrue,
      );
      expect(shifts.single.hasUnlinkedAssignees, isTrue);
    });

    test('a fully linked shift is not flagged', () {
      final schedule = _schedule(singleRobotConfig, slots: 1);
      final shifts = _import(
        schedule,
        uidByName: {
          for (final name in schedule.namesInSlot(0)) name: 'uid-$name',
        },
      );

      expect(shifts.single.hasUnlinkedAssignees, isFalse);
    });

    test('the name lookup ignores case, because a rotation is typed', () {
      final schedule = _schedule(singleRobotConfig, slots: 1);
      final known = schedule.namesInSlot(0).first;
      final shifts = _import(
        schedule,
        uidByName: {known.toUpperCase(): 'uid-known'},
      );

      final index = shifts.single.assignedNames.indexOf(known);
      expect(shifts.single.assignedUids[index], 'uid-known');
    });

    test('the same unlinked person gets the same stand-in uid', () {
      expect(PitShift.unlinkedUid('Ada'), PitShift.unlinkedUid(' ada '));
    });

    test('a stand-in uid cannot be mistaken for a real one', () {
      expect(PitShift.unlinkedUid('Ada'), contains(':'));
    });

    test('two shifts for the same unlinked person still conflict', () {
      final shifts = _import(_schedule(singleRobotConfig, slots: 1));
      final same = shifts.single.copyWith(updatedAt: now);
      final overlapping = PitShift(
        id: 'other',
        label: 'Pit duty, match 1',
        kind: ShiftKind.pitDuty,
        competition: same.competition,
        assignedUids: same.assignedUids,
        assignedNames: same.assignedNames,
        startMatch: 1,
        endMatch: 1,
        updatedAt: now,
      );

      expect(same.conflictsWith(overlapping), isTrue);
    });
  });

  group('a second import', () {
    test('finds what the last import left at this competition', () {
      final mine = _import(_schedule(singleRobotConfig, slots: 2));
      final handMade = PitShift(
        id: 'hand',
        label: 'Load in',
        kind: ShiftKind.loadIn,
        competition: 'Houston',
        assignedUids: const ['uid-1'],
        assignedNames: const ['Someone'],
        updatedAt: now,
      );

      final previous = DriverScheduleImport.previousImports([
        ...mine,
        handMade,
      ], 'Houston');

      expect(previous, hasLength(2));
      expect(previous.any((s) => s.id == 'hand'), isFalse);
    });

    test('does not see another competition\'s import', () {
      final elsewhere = _import(
        _schedule(singleRobotConfig, slots: 2),
        competition: 'Dallas',
      );

      expect(
        DriverScheduleImport.previousImports(elsewhere, 'Houston'),
        isEmpty,
      );
    });

    test('finds nothing on a first import, so nothing is asked', () {
      expect(
        DriverScheduleImport.previousImports(const <PitShift>[], 'Houston'),
        isEmpty,
      );
    });
  });
}

DriverSchedule _schedule(ScheduleConfig config, {required int slots}) =>
    DriverScheduleGenerator(random: Random(7)).generate(
      config,
      {
        for (final input in config.inputs)
          input.key: const ['Ada', 'Bo', 'Cy', 'Di'],
      },
      slots: slots,
      handoff: false,
    );

List<PitShift> _import(
  DriverSchedule schedule, {
  Map<String, String> uidByName = const {},
  String competition = 'Houston',
  String idPrefix = 'drv-1',
}) => DriverScheduleImport.toShifts(
  schedule: schedule,
  competition: competition,
  uidByName: uidByName,
  idPrefix: idPrefix,
  now: DateTime.utc(2026, 8, 14, 12),
);
