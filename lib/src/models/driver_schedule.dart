library;

class ScheduleRole {
  const ScheduleRole({required this.key, required this.label});

  final String key;

  final String label;
}

class ScheduleInput {
  const ScheduleInput({required this.key, required this.label, this.group});

  final String key;
  final String label;

  final String? group;
}

class RoleSource {
  const RoleSource({required this.roles, required this.inputs});

  final List<String> roles;
  final List<String> inputs;
}

class HandoffPair {
  const HandoffPair({required this.driver, required this.operator});

  final String driver;
  final String operator;
}

class ScheduleGroup {
  const ScheduleGroup({this.label, required this.roleKeys});

  final String? label;
  final List<String> roleKeys;
}

class AttendanceColumn {
  const AttendanceColumn({required this.label, required this.roleKeys});

  final String label;
  final List<String> roleKeys;
}

class AttendanceView {
  const AttendanceView({required this.label, required this.columns});

  final String label;
  final List<AttendanceColumn> columns;
}

class ScheduleConfig {
  const ScheduleConfig({
    required this.label,
    required this.roles,
    required this.inputs,
    this.sources,
    this.handoffPairs = const [],
    this.renderGroups,
    this.attendanceViews,
  });

  final String label;

  final List<ScheduleRole> roles;

  final List<ScheduleInput> inputs;

  final List<RoleSource>? sources;

  final List<HandoffPair> handoffPairs;

  final List<ScheduleGroup>? renderGroups;

  final List<AttendanceView>? attendanceViews;

  List<String> get roleKeys => [for (final role in roles) role.key];

  Map<String, String> get roleLabels => {
    for (final role in roles) role.key: role.label,
  };

  List<RoleSource> get effectiveSources =>
      sources ??
      [
        for (final role in roles)
          RoleSource(roles: [role.key], inputs: [role.key]),
      ];

  List<ScheduleGroup> get effectiveRenderGroups =>
      renderGroups ?? [ScheduleGroup(roleKeys: roleKeys)];

  List<AttendanceView> get effectiveAttendanceViews =>
      attendanceViews ??
      [
        AttendanceView(
          label: 'Total',
          columns: [
            for (final role in roles)
              AttendanceColumn(label: role.label, roleKeys: [role.key]),
          ],
        ),
      ];
}

const ScheduleConfig singleRobotConfig = ScheduleConfig(
  label: 'One robot',
  roles: [
    ScheduleRole(key: 'driver', label: 'Driver'),
    ScheduleRole(key: 'operator', label: 'Operator'),
    ScheduleRole(key: 'technician', label: 'Technician'),
    ScheduleRole(key: 'humanPlayer', label: 'Human player'),
  ],
  inputs: [
    ScheduleInput(key: 'driver', label: 'Driver'),
    ScheduleInput(key: 'operator', label: 'Operator'),
    ScheduleInput(key: 'technician', label: 'Technician'),
    ScheduleInput(key: 'humanPlayer', label: 'Human player'),
  ],
  handoffPairs: [HandoffPair(driver: 'driver', operator: 'operator')],
);

final ScheduleConfig twoRobotConfig = _multiRobotConfig(2);

final ScheduleConfig threeRobotConfig = _multiRobotConfig(3);

ScheduleConfig _multiRobotConfig(int robots) {
  const roles = [
    ('driver', 'Driver'),
    ('operator', 'Operator'),
    ('technician', 'Technician'),
    ('humanPlayer', 'Human player'),
  ];
  final ids = [for (var i = 1; i <= robots; i++) 'r$i'];
  final all = robots == 2 ? 'both robots' : 'all robots';
  List<AttendanceColumn> columnsFor(List<String> robotIds) => [
    for (final (role, label) in roles)
      AttendanceColumn(
        label: label,
        roleKeys: [for (final id in robotIds) '$id$role'],
      ),
  ];

  return ScheduleConfig(
    label: robots == 2 ? 'Two robots' : 'Three robots',
    roles: [
      for (final id in ids)
        for (final (role, label) in roles)
          ScheduleRole(key: '$id$role', label: label),
    ],
    inputs: [
      for (var i = 0; i < robots; i++) ...[
        ScheduleInput(
          key: '${ids[i]}driver',
          label: 'Driver',
          group: 'Robot ${i + 1}',
        ),
        ScheduleInput(
          key: '${ids[i]}operator',
          label: 'Operator',
          group: 'Robot ${i + 1}',
        ),
      ],
      ScheduleInput(
        key: 'sharedTechnician',
        label: 'Technician',
        group: 'Shared by $all',
      ),
      ScheduleInput(
        key: 'sharedHumanPlayer',
        label: 'Human player',
        group: 'Shared by $all',
      ),
    ],
    sources: [
      for (final (role, _) in roles)
        RoleSource(
          roles: [for (final id in ids) '$id$role'],
          inputs: [
            for (final id in ids)
              switch (role) {
                'technician' => 'sharedTechnician',
                'humanPlayer' => 'sharedHumanPlayer',
                _ => '$id$role',
              },
          ],
        ),
    ],
    handoffPairs: [
      for (final id in ids)
        HandoffPair(driver: '${id}driver', operator: '${id}operator'),
    ],
    renderGroups: [
      for (var i = 0; i < robots; i++)
        ScheduleGroup(
          label: 'Robot ${i + 1}',
          roleKeys: [for (final (role, _) in roles) '${ids[i]}$role'],
        ),
    ],
    attendanceViews: [
      AttendanceView(
        label: all[0].toUpperCase() + all.substring(1),
        columns: columnsFor(ids),
      ),
      for (var i = 0; i < robots; i++)
        AttendanceView(label: 'Robot ${i + 1}', columns: columnsFor([ids[i]])),
    ],
  );
}

final List<ScheduleConfig> scheduleConfigs = [
  singleRobotConfig,
  twoRobotConfig,
  threeRobotConfig,
];

class EventMatchSchedule {
  const EventMatchSchedule({
    required this.eventKey,
    required this.teams,
    required this.matchNumbers,
    required this.plays,
  });

  factory EventMatchSchedule.fromJson(Map<String, dynamic> json) {
    final matchNumbers = _ints(json['matchNumbers']);
    final plays = json['plays'];
    final eventKey = json['eventKey'];
    return EventMatchSchedule(
      eventKey: eventKey is String ? eventKey : '',
      teams: _ints(json['teams']),
      matchNumbers: matchNumbers,
      plays: [
        if (plays is List)
          for (final robot in plays)
            [
              for (final slot in _ints(robot))
                if (slot >= 0 && slot < matchNumbers.length) slot,
            ],
      ],
    );
  }

  final String eventKey;

  final List<int> teams;

  final List<int> matchNumbers;

  final List<List<int>> plays;

  List<({int match, List<int> robots})> get sharedMatches => [
    for (var slot = 0; slot < matchNumbers.length; slot++)
      if (plays.where((robot) => robot.contains(slot)).length > 1)
        (
          match: matchNumbers[slot],
          robots: [
            for (var robot = 0; robot < plays.length; robot++)
              if (plays[robot].contains(slot)) robot + 1,
          ],
        ),
  ];

  Map<String, dynamic> toJson() => {
    'eventKey': eventKey,
    'teams': teams,
    'matchNumbers': matchNumbers,
    'plays': plays,
  };

  static List<int> _ints(Object? value) => [
    if (value is List)
      for (final item in value)
        if (item is num) item.toInt(),
  ];
}

class DriverSchedule {
  DriverSchedule({
    required this.config,
    required this.slots,
    required this.handoff,
    required this._columns,
    required this._rosters,
    this.matches,
  });

  final ScheduleConfig config;

  final int slots;

  final EventMatchSchedule? matches;

  final bool handoff;

  final Map<String, List<String>> _columns;
  final Map<String, Set<String>> _rosters;

  String nameAt(String roleKey, int slot) {
    final column = _columns[roleKey];
    if (column == null || slot < 0 || slot >= column.length) return '';
    return column[slot];
  }

  Set<String> rosterFor(String roleKey) => _rosters[roleKey] ?? const {};

  List<String> get roleKeys => config.roleKeys;

  List<int> slotsFor(ScheduleGroup group) =>
      group.roleKeys.isEmpty ? const [] : slotsForRole(group.roleKeys.first);

  List<int> slotsForRole(String roleKey) {
    final plays = matches?.plays;
    final robot = _robotOf(roleKey);
    if (plays != null && robot >= 0 && robot < plays.length) {
      return plays[robot];
    }
    return [for (var slot = 0; slot < slots; slot++) slot];
  }

  int? teamFor(ScheduleGroup group) {
    final teams = matches?.teams;
    if (teams == null || group.roleKeys.isEmpty) return null;
    final robot = _robotOf(group.roleKeys.first);
    return robot >= 0 && robot < teams.length ? teams[robot] : null;
  }

  int _robotOf(String roleKey) => config.effectiveRenderGroups.indexWhere(
    (group) => group.roleKeys.contains(roleKey),
  );

  int matchAt(int slot) {
    final numbers = matches?.matchNumbers;
    return numbers != null && slot < numbers.length ? numbers[slot] : slot + 1;
  }

  String slotLabel(int slot) =>
      matches == null ? '${slot + 1}' : 'Q${matchAt(slot)}';

  bool isStaffed(String roleKey) => rosterFor(roleKey).isNotEmpty;

  List<String> shownRoleKeys(ScheduleGroup group) => [
    for (final key in group.roleKeys)
      if (isStaffed(key)) key,
  ];

  bool get isEmpty => config.roleKeys.every((key) => rosterFor(key).isEmpty);

  Set<String> namesInSlot(int slot) => {
    for (final key in config.roleKeys)
      if (nameAt(key, slot).isNotEmpty) nameAt(key, slot),
  };
}

class ScheduleHighlights {
  const ScheduleHighlights._({
    required this.conflicts,
    required this.backToBack,
    required this.handoffs,
    required this.handoffMissed,
  });

  final Set<String> conflicts;

  final Set<String> backToBack;

  final Set<String> handoffs;

  final int handoffMissed;

  static String _cell(int slot, String roleKey) => '$slot,$roleKey';

  bool isConflict(int slot, String roleKey) =>
      conflicts.contains(_cell(slot, roleKey));

  bool isBackToBack(int slot, String roleKey) =>
      backToBack.contains(_cell(slot, roleKey));

  bool isHandoff(int slot, String roleKey) =>
      handoffs.contains(_cell(slot, roleKey));

  bool get isQuiet =>
      conflicts.isEmpty &&
      backToBack.isEmpty &&
      handoffs.isEmpty &&
      handoffMissed == 0;

  factory ScheduleHighlights.of(DriverSchedule schedule) {
    final slots = schedule.slots;
    final roleKeys = schedule.roleKeys;

    final pairs = schedule.handoff
        ? schedule.config.handoffPairs
        : const <HandoffPair>[];

    final handoffs = <String>{};
    var handoffMissed = 0;
    for (final pair in pairs) {
      final played = schedule.slotsForRole(pair.driver);
      for (var i = 0; i < played.length - 1; i++) {
        final slot = played[i];
        final nextDriver = schedule.nameAt(pair.driver, played[i + 1]);
        if (nextDriver.isEmpty) continue;
        if (schedule.nameAt(pair.operator, slot) == nextDriver) {
          handoffs.add(_cell(slot, pair.operator));
        } else {
          handoffMissed++;
        }
      }
    }
    final operatorFor = {for (final pair in pairs) pair.driver: pair.operator};

    final conflicts = <String>{};
    for (var slot = 0; slot < slots; slot++) {
      final seen = <String, String>{};
      for (final roleKey in roleKeys) {
        final name = schedule.nameAt(roleKey, slot);
        if (name.isEmpty) continue;
        final firstRole = seen[name];
        if (firstRole == null) {
          seen[name] = roleKey;
        } else {
          conflicts
            ..add(_cell(slot, roleKey))
            ..add(_cell(slot, firstRole));
        }
      }
    }

    final backToBack = <String>{};
    for (var slot = 1; slot < slots; slot++) {
      final previous = schedule.namesInSlot(slot - 1);
      for (final roleKey in roleKeys) {
        final name = schedule.nameAt(roleKey, slot);
        if (name.isEmpty || !previous.contains(name)) continue;

        final operatorKey = operatorFor[roleKey];
        if (operatorKey != null &&
            schedule.nameAt(operatorKey, slot - 1) == name &&
            roleKeys.every(
              (other) =>
                  other == operatorKey ||
                  schedule.nameAt(other, slot - 1) != name,
            )) {
          continue;
        }
        backToBack.add(_cell(slot, roleKey));
        for (final other in roleKeys) {
          if (schedule.nameAt(other, slot - 1) == name) {
            backToBack.add(_cell(slot - 1, other));
          }
        }
      }
    }

    return ScheduleHighlights._(
      conflicts: conflicts,
      backToBack: backToBack,
      handoffs: handoffs,
      handoffMissed: handoffMissed,
    );
  }
}

class AttendanceEntry {
  const AttendanceEntry({
    required this.name,
    required this.counts,
    required this.total,
  });

  final String name;

  final List<int?> counts;

  final int total;
}

class AttendanceTable {
  const AttendanceTable._({required this.columns, required this.rows});

  final List<AttendanceColumn> columns;

  final List<AttendanceEntry> rows;

  factory AttendanceTable.of(DriverSchedule schedule, AttendanceView view) {
    final columns = [
      for (final column in view.columns)
        if (column.roleKeys.any(schedule.isStaffed)) column,
    ];
    final columnRosters = [
      for (final column in columns)
        <String>{
          for (final roleKey in column.roleKeys) ...schedule.rosterFor(roleKey),
        },
    ];

    final counts = <String, List<int>>{};
    final totals = <String, int>{};
    List<int> countsFor(String name) {
      totals.putIfAbsent(name, () => 0);
      return counts.putIfAbsent(
        name,
        () => List<int>.filled(columns.length, 0),
      );
    }

    for (final roster in columnRosters) {
      for (final name in roster) {
        countsFor(name);
      }
    }

    for (var slot = 0; slot < schedule.slots; slot++) {
      final counted = <String>{};
      for (var index = 0; index < columns.length; index++) {
        for (final roleKey in columns[index].roleKeys) {
          final name = schedule.nameAt(roleKey, slot);
          if (name.isEmpty) continue;
          countsFor(name)[index]++;
          if (counted.add(name)) totals[name] = totals[name]! + 1;
        }
      }
    }

    final rows = <AttendanceEntry>[];
    for (final entry in counts.entries) {
      final cells = <int?>[];
      for (var index = 0; index < columns.length; index++) {
        final count = entry.value[index];
        if (count > 0) {
          cells.add(count);
        } else {
          cells.add(columnRosters[index].contains(entry.key) ? 0 : null);
        }
      }
      rows.add(
        AttendanceEntry(
          name: entry.key,
          counts: cells,
          total: totals[entry.key]!,
        ),
      );
    }
    rows.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
    });

    return AttendanceTable._(columns: columns, rows: rows);
  }
}
