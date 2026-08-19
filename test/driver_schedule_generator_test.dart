import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/driver_schedule.dart';
import 'package:spectrumpit/src/services/driver_schedule_generator.dart';

int appearances(DriverSchedule schedule, String name, List<String> roleKeys) {
  var count = 0;
  for (var slot = 0; slot < schedule.slots; slot++) {
    for (final roleKey in roleKeys) {
      if (schedule.nameAt(roleKey, slot) == name) count++;
    }
  }
  return count;
}

DriverSchedule fixedSchedule({
  required ScheduleConfig config,
  required int slots,
  required bool handoff,
  required Map<String, List<String>> columns,
  Map<String, Set<String>>? rosters,
}) {
  return DriverSchedule(
    config: config,
    slots: slots,
    handoff: handoff,
    columns: columns,
    rosters:
        rosters ??
        {for (final entry in columns.entries) entry.key: entry.value.toSet()},
  );
}

void main() {
  group('parseNameList', () {
    test('splits on newlines and commas, trimming blanks', () {
      expect(parseNameList(' Alice \n Bob, Cara \n\n , '), [
        'Alice',
        'Bob',
        'Cara',
      ]);
    });

    test('keeps repeats and order, which are how a share is set', () {
      expect(parseNameList('Alice\nBob\nAlice'), ['Alice', 'Bob', 'Alice']);
    });

    test('an empty field is an empty list, not a blank name', () {
      expect(parseNameList('   \n , '), isEmpty);
    });
  });

  group('validateSlotCount', () {
    test('accepts a plain count', () {
      expect(validateSlotCount(' 12 '), isNull);
    });

    test('explains a missing or unreadable count', () {
      expect(validateSlotCount(''), isNotNull);
      expect(validateSlotCount('lots'), isNotNull);
    });

    test('explains a count below one or above the cap', () {
      expect(validateSlotCount('0'), isNotNull);
      expect(validateSlotCount('${maxScheduleSlots + 1}'), isNotNull);
      expect(validateSlotCount('$maxScheduleSlots'), isNull);
    });
  });

  group('generate', () {
    test('rejects a slot count outside the supported range', () {
      final generator = DriverScheduleGenerator(random: Random(1));
      expect(
        () => generator.generate(
          singleRobotConfig,
          const {},
          slots: 0,
          handoff: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => generator.generate(
          singleRobotConfig,
          const {},
          slots: maxScheduleSlots + 1,
          handoff: false,
        ),
        throwsArgumentError,
      );
    });

    test('the largest allowed rotation stays quick and still fills (#267)', () {
      final config = scheduleConfigs.last;
      final inputs = <String, List<String>>{
        for (final input in config.inputs)
          input.key: [for (var i = 0; i < 12; i++) 'Person $i'],
      };

      final elapsed = Stopwatch()..start();
      final schedule = DriverScheduleGenerator(random: Random(11))
          .generate(config, inputs, slots: maxScheduleSlots, handoff: true);
      elapsed.stop();

      expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
      for (final roleKey in config.roleKeys) {
        for (var slot = 0; slot < maxScheduleSlots; slot++) {
          expect(
            schedule.nameAt(roleKey, slot),
            isNotEmpty,
            reason: '$roleKey has a hole at slot $slot',
          );
        }
      }
    });

    test('spreads a role evenly when the slots divide by the names', () {
      final schedule = DriverScheduleGenerator(random: Random(3)).generate(
        singleRobotConfig,
        const {
          'driver': ['Alice', 'Bob', 'Cara'],
        },
        slots: 6,
        handoff: false,
      );

      for (final name in ['Alice', 'Bob', 'Cara']) {
        expect(
          appearances(schedule, name, ['driver']),
          2,
          reason: '$name should drive twice in six matches',
        );
      }
    });

    test('leaves a role nobody is listed for blank rather than crashing', () {
      final schedule = DriverScheduleGenerator(random: Random(4)).generate(
        singleRobotConfig,
        const {
          'driver': ['Alice'],
        },
        slots: 3,
        handoff: false,
      );

      expect(schedule.nameAt('driver', 0), 'Alice');
      expect(schedule.nameAt('technician', 0), '');
      expect(schedule.nameAt('nosuchrole', 0), '');
      expect(schedule.nameAt('driver', 99), '');
    });

    test("being on both robots' driver lists grants no extra turns", () {
      final schedule = DriverScheduleGenerator(random: Random(5)).generate(
        twoRobotConfig,
        const {
          'r1driver': ['Alice', 'Bob'],
          'r2driver': ['Alice', 'Cara'],
        },
        slots: 6,
        handoff: false,
      );

      final driverKeys = ['r1driver', 'r2driver'];
      expect(appearances(schedule, 'Alice', driverKeys), 4);
      expect(appearances(schedule, 'Bob', driverKeys), 4);
      expect(appearances(schedule, 'Cara', driverKeys), 4);
    });

    test("repeating a name inside one list raises that person's share", () {
      final schedule = DriverScheduleGenerator(random: Random(6)).generate(
        singleRobotConfig,
        const {
          'driver': ['Alice', 'Alice', 'Bob'],
        },
        slots: 6,
        handoff: false,
      );

      expect(appearances(schedule, 'Alice', ['driver']), 4);
      expect(appearances(schedule, 'Bob', ['driver']), 2);
    });

    test('two columns sharing one pool never draw the same person at once', () {
      for (var seed = 0; seed < 25; seed++) {
        final schedule = DriverScheduleGenerator(random: Random(seed)).generate(
          twoRobotConfig,
          const {
            'r1driver': ['Ada', 'Ben'],
            'r2driver': ['Cleo', 'Dev'],
            'r1operator': ['Eli', 'Fern'],
            'r2operator': ['Gus', 'Hana'],
            'sharedTechnician': ['Ines', 'Jae', 'Kit', 'Lou'],
            'sharedHumanPlayer': ['Mira', 'Nils', 'Opal', 'Pia'],
          },
          slots: 6,
          handoff: false,
        );

        expect(
          ScheduleHighlights.of(schedule).conflicts,
          isEmpty,
          reason: 'seed $seed put someone in two seats at once',
        );
      }
    });

    test("the hand-off makes each match's operator drive the next", () {
      final schedule = DriverScheduleGenerator(random: Random(7)).generate(
        singleRobotConfig,
        const {
          'driver': ['Alice', 'Bob', 'Cara'],
          'operator': ['Alice', 'Bob', 'Cara'],
        },
        slots: 6,
        handoff: true,
      );

      final highlights = ScheduleHighlights.of(schedule);
      expect(highlights.handoffs.length, greaterThanOrEqualTo(3));

      for (final name in ['Alice', 'Bob', 'Cara']) {
        expect(
          appearances(schedule, name, ['operator']),
          2,
          reason: 'the hand-off changed how often $name operates',
        );
      }
    });
  });

  group('ScheduleHighlights', () {
    Map<String, List<String>> handoffShaped() => {
      'driver': ['Alice', 'Bob'],
      'operator': ['Bob', 'Cara'],
      'technician': ['Dan', 'Eve'],
      'humanPlayer': ['Fay', 'Gus'],
    };

    test('flags the repeat as back-to-back when no hand-off was asked for', () {
      final highlights = ScheduleHighlights.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 2,
          handoff: false,
          columns: handoffShaped(),
        ),
      );

      expect(highlights.isBackToBack(1, 'driver'), isTrue);
      expect(highlights.isBackToBack(0, 'operator'), isTrue);
      expect(highlights.isHandoff(0, 'operator'), isFalse);
    });

    test('excuses the same repeat when the hand-off was asked for', () {
      final highlights = ScheduleHighlights.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 2,
          handoff: true,
          columns: handoffShaped(),
        ),
      );

      expect(highlights.isBackToBack(1, 'driver'), isFalse);
      expect(highlights.isHandoff(0, 'operator'), isTrue);
      expect(highlights.handoffMissed, 0);
    });

    test('marks both cells of a same-slot conflict', () {
      final highlights = ScheduleHighlights.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 1,
          handoff: false,
          columns: {
            'driver': ['Alice'],
            'operator': ['Alice'],
            'technician': ['Bob'],
            'humanPlayer': ['Cara'],
          },
        ),
      );

      expect(highlights.isConflict(0, 'driver'), isTrue);
      expect(highlights.isConflict(0, 'operator'), isTrue);
      expect(highlights.isConflict(0, 'technician'), isFalse);
    });

    test('counts a hand-off that could not be arranged', () {
      final highlights = ScheduleHighlights.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 2,
          handoff: true,
          columns: {
            'driver': ['Alice', 'Bob'],
            'operator': ['Cara', 'Dan'],
            'technician': ['Eve', 'Fay'],
            'humanPlayer': ['Gus', 'Hal'],
          },
        ),
      );

      expect(highlights.handoffMissed, 1);
      expect(highlights.handoffs, isEmpty);
    });

    test('a clean rotation has nothing to explain', () {
      final highlights = ScheduleHighlights.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 2,
          handoff: false,
          columns: {
            'driver': ['Alice', 'Bob'],
            'operator': ['Cara', 'Dan'],
            'technician': ['Eve', 'Fay'],
            'humanPlayer': ['Gus', 'Hal'],
          },
        ),
      );

      expect(highlights.isQuiet, isTrue);
    });
  });

  group('AttendanceTable', () {
    test('someone on a list who got no slot reads zero, not nothing', () {
      final table = AttendanceTable.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 1,
          handoff: false,
          columns: {
            'driver': ['Alice'],
            'operator': ['Bob'],
            'technician': ['Cara'],
            'humanPlayer': ['Dan'],
          },
          rosters: {
            'driver': {'Alice', 'Zoe'},
            'operator': {'Bob'},
            'technician': {'Cara'},
            'humanPlayer': {'Dan'},
          },
        ),
        singleRobotConfig.effectiveAttendanceViews.single,
      );

      final zoe = table.rows.firstWhere((row) => row.name == 'Zoe');
      expect(zoe.total, 0);

      expect(zoe.counts, [0, null, null, null]);
    });

    test('busiest first, then alphabetical', () {
      final table = AttendanceTable.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 2,
          handoff: false,
          columns: {
            'driver': ['Alice', 'Alice'],
            'operator': ['Bob', 'Cara'],
            'technician': ['', ''],
            'humanPlayer': ['', ''],
          },
          rosters: {
            'driver': {'Alice'},
            'operator': {'Bob', 'Cara'},
            'technician': <String>{},
            'humanPlayer': <String>{},
          },
        ),
        singleRobotConfig.effectiveAttendanceViews.single,
      );

      expect(
        [for (final row in table.rows) row.name],
        ['Alice', 'Bob', 'Cara'],
      );
      expect(table.rows.first.total, 2);
    });

    test('a person in two roles in one match still attends one match', () {
      final table = AttendanceTable.of(
        fixedSchedule(
          config: singleRobotConfig,
          slots: 1,
          handoff: false,
          columns: {
            'driver': ['Alice'],
            'operator': ['Alice'],
            'technician': ['Bob'],
            'humanPlayer': ['Cara'],
          },
        ),
        singleRobotConfig.effectiveAttendanceViews.single,
      );

      final alice = table.rows.firstWhere((row) => row.name == 'Alice');
      expect(alice.counts, [1, 1, null, null]);
      expect(alice.total, 1);
    });

    test('the both-robots view totals a role across the two robots', () {
      final schedule = fixedSchedule(
        config: twoRobotConfig,
        slots: 2,
        handoff: false,
        columns: {
          'r1driver': ['Alice', 'Bob'],
          'r1operator': ['Cara', 'Dan'],
          'r1technician': ['Eve', 'Fay'],
          'r1humanPlayer': ['Gus', 'Hal'],
          'r2driver': ['Ida', 'Alice'],
          'r2operator': ['Jan', 'Kai'],
          'r2technician': ['Fay', 'Eve'],
          'r2humanPlayer': ['Hal', 'Gus'],
        },
      );
      final views = twoRobotConfig.effectiveAttendanceViews;

      final both = AttendanceTable.of(schedule, views[0]);
      final alice = both.rows.firstWhere((row) => row.name == 'Alice');

      expect(alice.counts.first, 2);
      expect(alice.total, 2);

      final robotOne = AttendanceTable.of(schedule, views[1]);
      expect(
        robotOne.rows.firstWhere((row) => row.name == 'Alice').counts.first,
        1,
      );
      final robotTwo = AttendanceTable.of(schedule, views[2]);
      expect(
        robotTwo.rows.firstWhere((row) => row.name == 'Alice').counts.first,
        1,
      );
    });
  });

  group('scheduleAsTabSeparatedText', () {
    test('writes a header and one row per match', () {
      final schedule = fixedSchedule(
        config: singleRobotConfig,
        slots: 2,
        handoff: false,
        columns: {
          'driver': ['Alice', 'Bob'],
          'operator': ['Cara', 'Dan'],
          'technician': ['Eve', 'Fay'],
          'humanPlayer': ['Gus', 'Hal'],
        },
      );

      expect(
        scheduleAsTabSeparatedText(
          schedule,
          singleRobotConfig.effectiveRenderGroups.single,
        ),
        '#\tDriver\tOperator\tTechnician\tHuman player\n'
        '1\tAlice\tCara\tEve\tGus\n'
        '2\tBob\tDan\tFay\tHal',
      );
    });

    test('an unfilled seat reads as a dash', () {
      final schedule = fixedSchedule(
        config: singleRobotConfig,
        slots: 1,
        handoff: false,
        columns: {
          'driver': ['Alice'],
          'operator': [''],
          'technician': [''],
          'humanPlayer': [''],
        },
      );

      expect(
        scheduleAsTabSeparatedText(
          schedule,
          singleRobotConfig.effectiveRenderGroups.single,
        ),
        '#\tDriver\tOperator\tTechnician\tHuman player\n1\tAlice\t-\t-\t-',
      );
    });

    test('a two-robot chart exports only its own robot', () {
      final schedule = fixedSchedule(
        config: twoRobotConfig,
        slots: 1,
        handoff: false,
        columns: {
          'r1driver': ['Alice'],
          'r1operator': ['Bob'],
          'r1technician': ['Cara'],
          'r1humanPlayer': ['Dan'],
          'r2driver': ['Eve'],
          'r2operator': ['Fay'],
          'r2technician': ['Gus'],
          'r2humanPlayer': ['Hal'],
        },
      );

      final text = scheduleAsTabSeparatedText(
        schedule,
        twoRobotConfig.effectiveRenderGroups[1],
      );
      expect(text, contains('Eve'));
      expect(text, isNot(contains('Alice')));
    });
  });

  group('config', () {
    test('every source input is a field the crew can actually fill in', () {
      for (final config in scheduleConfigs) {
        final offered = {for (final input in config.inputs) input.key};
        for (final source in config.effectiveSources) {
          for (final input in source.inputs) {
            expect(
              offered,
              contains(input),
              reason: '${config.label} draws on "$input" with no field for it',
            );
          }
        }
      }
    });

    test('every role is filled by exactly one source', () {
      for (final config in scheduleConfigs) {
        final filled = [
          for (final source in config.effectiveSources) ...source.roles,
        ];
        expect(filled..sort(), (config.roleKeys.toList()..sort()));
      }
    });

    test('charts and attendance views cover every role', () {
      for (final config in scheduleConfigs) {
        final charted = {
          for (final group in config.effectiveRenderGroups) ...group.roleKeys,
        };
        expect(charted, config.roleKeys.toSet());

        for (final view in config.effectiveAttendanceViews) {
          final counted = {
            for (final column in view.columns) ...column.roleKeys,
          };
          expect(
            config.roleKeys.toSet().containsAll(counted),
            isTrue,
            reason: '${view.label} counts a role the config does not have',
          );
        }
      }
    });

    test('a hand-off pair names two real roles', () {
      for (final config in scheduleConfigs) {
        for (final pair in config.handoffPairs) {
          expect(config.roleKeys, contains(pair.driver));
          expect(config.roleKeys, contains(pair.operator));
        }
      }
    });
  });
}
