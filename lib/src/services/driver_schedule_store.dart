import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/driver_schedule.dart';

class DriverScheduleStore {
  DriverScheduleStore({Future<SharedPreferences> Function()? prefsLoader})
    : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String _prefix = 'driver_schedule_';

  final Future<SharedPreferences> Function() _prefsLoader;

  static String keyFor(String competition) => '$_prefix$competition';

  Future<SavedDriverSchedule?> load(String competition) async {
    if (competition.isEmpty) {
      return null;
    }
    final raw = (await _prefsLoader()).getString(keyFor(competition));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return SavedDriverSchedule.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String competition, SavedDriverSchedule saved) async {
    if (competition.isEmpty) {
      return;
    }
    final prefs = await _prefsLoader();
    await prefs.setString(keyFor(competition), jsonEncode(saved.toJson()));
  }

  Future<void> clear(String competition) async =>
      (await _prefsLoader()).remove(keyFor(competition));
}

class SavedDriverSchedule {
  const SavedDriverSchedule({
    required this.mode,
    required this.slots,
    required this.handoff,
    required this.inputs,
    required this.grid,
    required this.updatedAt,
  });

  factory SavedDriverSchedule.fromJson(Map<String, dynamic> json) {
    return SavedDriverSchedule(
      mode: json['mode'] as String? ?? '',
      slots: (json['slots'] as num?)?.toInt() ?? 0,
      handoff: json['handoff'] as bool? ?? false,
      inputs: _stringLists(json['inputs']),
      grid: _stringLists(json['grid']),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String mode;

  final int slots;
  final bool handoff;

  final Map<String, List<String>> inputs;

  final Map<String, List<String>> grid;

  final DateTime updatedAt;

  ScheduleConfig? get config {
    for (final candidate in scheduleConfigs) {
      if (candidate.label == mode) {
        return candidate;
      }
    }
    return null;
  }

  DriverSchedule? toSchedule() {
    final found = config;
    if (found == null) {
      return null;
    }
    return DriverSchedule(
      config: found,
      slots: slots,
      handoff: handoff,
      columns: {
        for (final role in found.roleKeys) role: grid[role] ?? const <String>[],
      },

      rosters: {
        for (final role in found.roleKeys)
          role: {
            for (final name in grid[role] ?? const <String>[])
              if (name.isNotEmpty) name,
          },
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'slots': slots,
    'handoff': handoff,
    'inputs': inputs,
    'grid': grid,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static Map<String, List<String>> _stringLists(Object? value) {
    if (value is! Map) {
      return const <String, List<String>>{};
    }
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: (entry.value as List).whereType<String>().toList(
            growable: false,
          ),
    };
  }
}
