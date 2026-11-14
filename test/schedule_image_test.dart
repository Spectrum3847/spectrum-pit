import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/driver_schedule.dart';
import 'package:spectrumpit/src/services/driver_schedule_generator.dart';
import 'package:spectrumpit/src/services/schedule_image.dart';

void main() {
  testWidgets('draws a chart as a PNG named for the event and robot', (
    tester,
  ) async {
    final schedule = DriverScheduleGenerator(random: Random(1)).generate(
      twoRobotConfig,
      const {
        'r1driver': ['Ada', 'Ben'],
        'r2driver': ['Cy'],
      },
      matches: const EventMatchSchedule(
        eventKey: '2026txhou',
        teams: [3847, 118],
        matchNumbers: [4, 9, 12],
        plays: [
          [0, 2],
          [1],
        ],
      ),
      handoff: false,
    );

    final image = (await tester.runAsync(
      () => scheduleImage(schedule, twoRobotConfig.effectiveRenderGroups[0]),
    ))!;

    expect(image.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(image.title, 'Robot 1, team 3847');
    expect(image.fileName, '2026txhou-robot-1-team-3847-schedule.png');

    final decoded = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(image.bytes);
      return (await codec.getNextFrame()).image;
    }))!;
    expect(decoded.height, (24 + 64 + 34 + 2 * 32 + 24) * 2);
  });

  testWidgets('a numbered rotation is named for the schedule alone', (
    tester,
  ) async {
    final schedule = DriverScheduleGenerator(random: Random(1)).generate(
      singleRobotConfig,
      const {
        'driver': ['Ada'],
      },
      slots: 2,
      handoff: false,
    );

    final image = (await tester.runAsync(
      () => scheduleImage(
        schedule,
        singleRobotConfig.effectiveRenderGroups.single,
      ),
    ))!;

    expect(image.title, 'Drive team schedule');
    expect(image.fileName, 'schedule.png');
  });
}
