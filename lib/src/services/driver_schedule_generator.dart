library;

import 'dart:math';

import '../models/driver_schedule.dart';

const int maxScheduleSlots = 500;

List<String> parseNameList(String text) => text
    .split(RegExp(r'[\n,]+'))
    .map((name) => name.trim())
    .where((name) => name.isNotEmpty)
    .toList();

String? validateSlotCount(String text) {
  final value = int.tryParse(text.trim());
  if (value == null) return 'Enter how many matches to schedule';
  if (value < 1) return 'Schedule at least 1 match';
  if (value > maxScheduleSlots) {
    return 'Schedule at most $maxScheduleSlots matches';
  }
  return null;
}

String scheduleAsTabSeparatedText(
  DriverSchedule schedule,
  ScheduleGroup group,
) {
  final labels = schedule.config.roleLabels;
  final lines = <String>[
    ['#', for (final key in group.roleKeys) labels[key] ?? key].join('\t'),
  ];
  for (var slot = 0; slot < schedule.slots; slot++) {
    lines.add(
      [
        '${slot + 1}',
        for (final key in group.roleKeys)
          schedule.nameAt(key, slot).isEmpty ? '-' : schedule.nameAt(key, slot),
      ].join('\t'),
    );
  }
  return lines.join('\n');
}

class DriverScheduleGenerator {
  DriverScheduleGenerator({Random? random}) : _random = random ?? Random();

  final Random _random;

  DriverSchedule generate(
    ScheduleConfig config,
    Map<String, List<String>> inputs, {
    required int slots,
    required bool handoff,
  }) {
    if (slots < 1 || slots > maxScheduleSlots) {
      throw ArgumentError.value(slots, 'slots', 'must be 1..$maxScheduleSlots');
    }

    final columns = <String, List<String>>{};
    final rosters = <String, Set<String>>{};
    for (final source in config.effectiveSources) {
      final lists = [
        for (final key in source.inputs) inputs[key] ?? const <String>[],
      ];
      final filled = _pooledSpread(lists, slots);
      for (var index = 0; index < source.roles.length; index++) {
        rosters[source.roles[index]] = {...lists[index]};
        columns[source.roles[index]] = filled[index];
      }
    }

    final roleKeys = config.roleKeys;

    _resolveConflicts(columns, slots, roleKeys);
    for (var round = 0; round < 20; round++) {
      final movedAdjacent = _resolveBackToBack(columns, slots, roleKeys);
      final movedConflict = _resolveConflicts(columns, slots, roleKeys);
      if (!movedAdjacent && !movedConflict) break;
    }

    if (handoff) {
      for (final pair in config.handoffPairs) {
        _spreadForHandoff(columns, slots, pair, roleKeys);
        _applyHandoff(columns, slots, pair, roleKeys);
      }
    }

    return DriverSchedule(
      config: config,
      slots: slots,
      handoff: handoff,
      columns: columns,
      rosters: rosters,
    );
  }

  List<List<String>> _pooledSpread(List<List<String>> lists, int slots) {
    final count = lists.length;
    final columns = List.generate(count, (_) => List<String>.filled(slots, ''));
    final weight = <String, int>{};
    final eligible = <String, Set<int>>{};
    final priority = <String, int>{};
    for (var column = 0; column < count; column++) {
      final local = <String, int>{};
      for (var index = 0; index < lists[column].length; index++) {
        final name = lists[column][index];
        local[name] = (local[name] ?? 0) + 1;
        priority.putIfAbsent(name, () => index);
      }
      local.forEach((name, listed) {
        weight[name] = max(weight[name] ?? 0, listed);
        eligible.putIfAbsent(name, () => <int>{}).add(column);
      });
    }

    final names = weight.keys.toList();
    final assigned = {for (final name in names) name: 0};
    final previousInColumn = List<String>.filled(count, '');
    for (var slot = 0; slot < slots; slot++) {
      final used = <String>{};
      for (var column = 0; column < count; column++) {
        final candidates = [
          for (final name in names)
            if (eligible[name]!.contains(column)) name,
        ];

        if (candidates.isEmpty) continue;

        var fairest = double.infinity;
        for (final name in candidates) {
          fairest = min(fairest, assigned[name]! / weight[name]!);
        }
        final ties = [
          for (final name in candidates)
            if ((assigned[name]! / weight[name]! - fairest).abs() < 1e-9) name,
        ];
        var preferred = [
          for (final name in ties)
            if (name != previousInColumn[column] && !used.contains(name)) name,
        ];
        if (preferred.isEmpty) {
          preferred = [
            for (final name in ties)
              if (!used.contains(name)) name,
          ];
        }
        if (preferred.isEmpty) {
          preferred = [
            for (final name in ties)
              if (name != previousInColumn[column]) name,
          ];
        }
        if (preferred.isEmpty) preferred = ties;

        final picked = preferred.length == 1
            ? preferred.first
            : _pickByPriority(preferred, priority);
        columns[column][slot] = picked;
        used.add(picked);
        assigned[picked] = assigned[picked]! + 1;
        previousInColumn[column] = picked;
      }
    }
    return columns;
  }

  String _pickByPriority(List<String> candidates, Map<String, int> priority) {
    final ordered = [...candidates]
      ..sort((a, b) => priority[a]!.compareTo(priority[b]!));
    final weights = [
      for (var i = 0; i < ordered.length; i++) ordered.length - i,
    ];
    final total = weights.reduce((a, b) => a + b);
    var roll = _random.nextDouble() * total;
    for (var index = 0; index < ordered.length; index++) {
      roll -= weights[index];
      if (roll <= 0) return ordered[index];
    }
    return ordered.last;
  }

  bool _resolveConflicts(
    Map<String, List<String>> columns,
    int slots,
    List<String> roleKeys,
  ) {
    var changed = false;
    for (var pass = 0; pass < 300; pass++) {
      var improved = false;
      for (var slot = 0; slot < slots; slot++) {
        final seen = <String>{};
        for (final roleKey in roleKeys) {
          final name = _at(columns, roleKey, slot);
          if (name.isEmpty) continue;
          if (seen.add(name)) continue;

          for (var other = 0; other < slots; other++) {
            if (other == slot) continue;
            final candidate = _at(columns, roleKey, other);
            if (candidate.isEmpty || candidate == name) continue;
            if (_othersIn(
              columns,
              slot,
              roleKey,
              roleKeys,
            ).contains(candidate)) {
              continue;
            }
            if (_othersIn(columns, other, roleKey, roleKeys).contains(name)) {
              continue;
            }
            _swap(columns, roleKey, slot, other);
            improved = true;
            break;
          }
        }
      }
      if (!improved) break;
      changed = true;
    }
    return changed;
  }

  bool _resolveBackToBack(
    Map<String, List<String>> columns,
    int slots,
    List<String> roleKeys,
  ) {
    var changed = false;
    for (var pass = 0; pass < 300; pass++) {
      var improved = false;
      for (var slot = 1; slot < slots; slot++) {
        final previous = _namesIn(columns, slot - 1, roleKeys);
        for (final roleKey in roleKeys) {
          final name = _at(columns, roleKey, slot);
          if (name.isEmpty || !previous.contains(name)) continue;
          for (var other = 0; other < slots; other++) {
            if (other == slot) continue;
            final candidate = _at(columns, roleKey, other);

            if (candidate.isEmpty || previous.contains(candidate)) continue;
            if (_othersIn(
              columns,
              slot,
              roleKey,
              roleKeys,
            ).contains(candidate)) {
              continue;
            }
            if (_othersIn(columns, other, roleKey, roleKeys).contains(name)) {
              continue;
            }

            if (other > 0 &&
                other - 1 != slot &&
                _namesIn(columns, other - 1, roleKeys).contains(name)) {
              continue;
            }
            if (other < slots - 1 &&
                other + 1 != slot &&
                _namesIn(columns, other + 1, roleKeys).contains(name)) {
              continue;
            }
            _swap(columns, roleKey, slot, other);
            improved = true;
            break;
          }
        }
      }
      if (!improved) break;
      changed = true;
    }
    return changed;
  }

  void _spreadForHandoff(
    Map<String, List<String>> columns,
    int slots,
    HandoffPair pair,
    List<String> roleKeys,
  ) {
    final driverColumn = columns[pair.driver];
    if (driverColumn == null) return;

    final pool = <String, int>{};
    for (final name in driverColumn) {
      if (name.isNotEmpty) pool[name] = (pool[name] ?? 0) + 1;
    }

    final outsidePair = [
      for (final key in roleKeys)
        if (key != pair.driver && key != pair.operator) key,
    ];
    Set<String> fixedAt(int slot) => _namesIn(columns, slot, outsidePair);

    final out = List<String>.filled(slots, '');
    for (var slot = 0; slot < slots; slot++) {
      final clash = fixedAt(slot);
      final adjacent = slot > 0 ? fixedAt(slot - 1) : <String>{};
      final previous = slot > 0 ? out[slot - 1] : '';
      final twoBack = slot > 1 ? out[slot - 2] : '';
      if (previous.isNotEmpty) adjacent.add(previous);

      final rules = <bool Function(String)>[
        (name) =>
            !clash.contains(name) &&
            name != twoBack &&
            !adjacent.contains(name),
        (name) => !clash.contains(name) && name != twoBack && name != previous,
        (name) => !clash.contains(name) && name != previous,
        (name) => !clash.contains(name),
        (name) => true,
      ];

      var picked = '';
      for (final rule in rules) {
        var most = 0;
        final ties = <String>[];
        pool.forEach((name, left) {
          if (left == 0 || !rule(name)) return;
          if (left > most) {
            most = left;
            ties
              ..clear()
              ..add(name);
          } else if (left == most) {
            ties.add(name);
          }
        });
        if (ties.isNotEmpty) {
          picked = ties[_random.nextInt(ties.length)];
          break;
        }
      }

      if (picked.isEmpty) break;
      out[slot] = picked;
      pool[picked] = pool[picked]! - 1;
    }
    columns[pair.driver] = out;
  }

  void _applyHandoff(
    Map<String, List<String>> columns,
    int slots,
    HandoffPair pair,
    List<String> roleKeys,
  ) {
    final operatorColumn = columns[pair.operator];
    if (columns[pair.driver] == null || operatorColumn == null) return;

    final pool = <String, int>{};
    for (final name in operatorColumn) {
      if (name.isNotEmpty) pool[name] = (pool[name] ?? 0) + 1;
    }

    final out = List<String>.filled(slots, '');
    for (var slot = 0; slot < slots - 1; slot++) {
      final wanted = _at(columns, pair.driver, slot + 1);
      if (wanted.isEmpty || (pool[wanted] ?? 0) == 0) continue;
      if (_othersIn(columns, slot, pair.operator, roleKeys).contains(wanted)) {
        continue;
      }
      pool[wanted] = pool[wanted]! - 1;
      out[slot] = wanted;
    }

    final spare = <String>[];
    pool.forEach((name, left) {
      for (var i = 0; i < left; i++) {
        spare.add(name);
      }
    });
    for (var slot = 0; slot < slots && spare.isNotEmpty; slot++) {
      if (out[slot].isNotEmpty) continue;
      final clash = _othersIn(columns, slot, pair.operator, roleKeys);
      final before = slot > 0 ? out[slot - 1] : '';
      final after = slot < slots - 1 ? out[slot + 1] : '';
      var index = spare.indexWhere(
        (name) => !clash.contains(name) && name != before && name != after,
      );
      if (index < 0) index = spare.indexWhere((name) => !clash.contains(name));
      if (index < 0) index = 0;
      out[slot] = spare.removeAt(index);
    }
    columns[pair.operator] = out;
  }

  static String _at(
    Map<String, List<String>> columns,
    String roleKey,
    int slot,
  ) {
    final column = columns[roleKey];
    if (column == null || slot < 0 || slot >= column.length) return '';
    return column[slot];
  }

  static Set<String> _namesIn(
    Map<String, List<String>> columns,
    int slot,
    List<String> roleKeys,
  ) => {
    for (final key in roleKeys)
      if (_at(columns, key, slot).isNotEmpty) _at(columns, key, slot),
  };

  static Set<String> _othersIn(
    Map<String, List<String>> columns,
    int slot,
    String roleKey,
    List<String> roleKeys,
  ) => {
    for (final key in roleKeys)
      if (key != roleKey && _at(columns, key, slot).isNotEmpty)
        _at(columns, key, slot),
  };

  static void _swap(
    Map<String, List<String>> columns,
    String roleKey,
    int a,
    int b,
  ) {
    final column = columns[roleKey]!;
    final held = column[a];
    column[a] = column[b];
    column[b] = held;
  }
}
