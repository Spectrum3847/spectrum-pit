import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/driver_schedule.dart';
import 'package:spectrumpit/src/services/driver_schedule_generator.dart';
import 'package:spectrumpit/src/services/driver_schedule_store.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  final names = {
    for (final input in singleRobotConfig.inputs)
      input.key: const ['Ada', 'Bo', 'Cy', 'Di'],
  };

  DriverSchedule generate(ScheduleConfig config, {int slots = 5}) =>
      DriverScheduleGenerator(random: Random(7)).generate(
        config,
        {
          for (final input in config.inputs)
            input.key: const ['Ada', 'Bo', 'Cy', 'Di'],
        },
        slots: slots,
        handoff: false,
      );

  SavedDriverSchedule saved(DriverSchedule schedule) => SavedDriverSchedule(
    mode: schedule.config.label,
    slots: schedule.slots,
    handoff: schedule.handoff,
    inputs: names,
    grid: {
      for (final role in schedule.config.roleKeys)
        role: [
          for (var slot = 0; slot < schedule.slots; slot++)
            schedule.nameAt(role, slot),
        ],
    },
    updatedAt: DateTime.utc(2026, 8, 14, 12),
  );

  test('nothing is saved for a competition that has none', () async {
    expect(await DriverScheduleStore().load('Houston'), isNull);
  });

  test('a rotation comes back exactly as it was generated', () async {
    final store = DriverScheduleStore();
    final original = generate(singleRobotConfig);
    await store.save('Houston', saved(original));

    final restored = (await store.load('Houston'))!.toSchedule()!;

    expect(restored.slots, original.slots);
    expect(restored.config.label, original.config.label);
    for (final role in original.config.roleKeys) {
      for (var slot = 0; slot < original.slots; slot++) {
        expect(
          restored.nameAt(role, slot),
          original.nameAt(role, slot),
          reason: 'the rotation must not be a re-roll',
        );
      }
    }
  });

  test('the typed names come back so the form is not empty', () async {
    final store = DriverScheduleStore();
    await store.save('Houston', saved(generate(singleRobotConfig)));

    expect((await store.load('Houston'))!.inputs, names);
  });

  test('a two-robot rotation round trips with both robots', () async {
    final store = DriverScheduleStore();
    final original = generate(twoRobotConfig, slots: 3);
    await store.save('Houston', saved(original));

    final restored = (await store.load('Houston'))!.toSchedule()!;

    expect(restored.config.label, twoRobotConfig.label);
    expect(restored.nameAt('r2driver', 0), original.nameAt('r2driver', 0));
  });

  test('two competitions keep their own rotations', () async {
    final store = DriverScheduleStore();
    await store.save('Houston', saved(generate(singleRobotConfig, slots: 5)));
    await store.save('Dallas', saved(generate(singleRobotConfig, slots: 2)));

    expect((await store.load('Houston'))!.slots, 5);
    expect((await store.load('Dallas'))!.slots, 2);
  });

  test('saving again replaces the previous rotation', () async {
    final store = DriverScheduleStore();
    await store.save('Houston', saved(generate(singleRobotConfig, slots: 5)));
    await store.save('Houston', saved(generate(singleRobotConfig, slots: 9)));

    expect((await store.load('Houston'))!.slots, 9);
  });

  test('a rotation that will not decode reads as none', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      DriverScheduleStore.keyFor('Houston'): 'not json',
    });

    expect(await DriverScheduleStore().load('Houston'), isNull);
  });

  test('a saved mode that no longer exists reads as no schedule', () async {
    final store = DriverScheduleStore();
    await store.save(
      'Houston',
      SavedDriverSchedule(
        mode: 'Three robots',
        slots: 2,
        handoff: false,
        inputs: const {},
        grid: const {},
        updatedAt: DateTime.utc(2026),
      ),
    );

    final loaded = (await store.load('Houston'))!;
    expect(loaded.config, isNull);
    expect(loaded.toSchedule(), isNull);
    expect(
      loaded.inputs,
      isNotNull,
      reason: 'the typed names are still worth handing back',
    );
  });

  test('an empty competition is not stored under a stray key', () async {
    final store = DriverScheduleStore();
    await store.save('', saved(generate(singleRobotConfig)));

    expect(await store.load(''), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.startsWith('driver_schedule_')),
      isEmpty,
    );
  });

  test('clearing removes it', () async {
    final store = DriverScheduleStore();
    await store.save('Houston', saved(generate(singleRobotConfig)));
    await store.clear('Houston');

    expect(await store.load('Houston'), isNull);
  });
}
