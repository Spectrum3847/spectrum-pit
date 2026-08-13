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

const ScheduleConfig twoRobotConfig = ScheduleConfig(
  label: 'Two robots',
  roles: [
    ScheduleRole(key: 'r1driver', label: 'Driver'),
    ScheduleRole(key: 'r1operator', label: 'Operator'),
    ScheduleRole(key: 'r1technician', label: 'Technician'),
    ScheduleRole(key: 'r1humanPlayer', label: 'Human player'),
    ScheduleRole(key: 'r2driver', label: 'Driver'),
    ScheduleRole(key: 'r2operator', label: 'Operator'),
    ScheduleRole(key: 'r2technician', label: 'Technician'),
    ScheduleRole(key: 'r2humanPlayer', label: 'Human player'),
  ],
  inputs: [
    ScheduleInput(key: 'r1driver', label: 'Driver', group: 'Robot 1'),
    ScheduleInput(key: 'r1operator', label: 'Operator', group: 'Robot 1'),
    ScheduleInput(key: 'r2driver', label: 'Driver', group: 'Robot 2'),
    ScheduleInput(key: 'r2operator', label: 'Operator', group: 'Robot 2'),
    ScheduleInput(
      key: 'sharedTechnician',
      label: 'Technician',
      group: 'Shared by both robots',
    ),
    ScheduleInput(
      key: 'sharedHumanPlayer',
      label: 'Human player',
      group: 'Shared by both robots',
    ),
  ],
  sources: [
    RoleSource(
      roles: ['r1driver', 'r2driver'],
      inputs: ['r1driver', 'r2driver'],
    ),
    RoleSource(
      roles: ['r1operator', 'r2operator'],
      inputs: ['r1operator', 'r2operator'],
    ),
    RoleSource(
      roles: ['r1technician', 'r2technician'],
      inputs: ['sharedTechnician', 'sharedTechnician'],
    ),
    RoleSource(
      roles: ['r1humanPlayer', 'r2humanPlayer'],
      inputs: ['sharedHumanPlayer', 'sharedHumanPlayer'],
    ),
  ],
  handoffPairs: [
    HandoffPair(driver: 'r1driver', operator: 'r1operator'),
    HandoffPair(driver: 'r2driver', operator: 'r2operator'),
  ],
  renderGroups: [
    ScheduleGroup(
      label: 'Robot 1',
      roleKeys: ['r1driver', 'r1operator', 'r1technician', 'r1humanPlayer'],
    ),
    ScheduleGroup(
      label: 'Robot 2',
      roleKeys: ['r2driver', 'r2operator', 'r2technician', 'r2humanPlayer'],
    ),
  ],
  attendanceViews: [
    AttendanceView(
      label: 'Both robots',
      columns: [
        AttendanceColumn(label: 'Driver', roleKeys: ['r1driver', 'r2driver']),
        AttendanceColumn(
          label: 'Operator',
          roleKeys: ['r1operator', 'r2operator'],
        ),
        AttendanceColumn(
          label: 'Technician',
          roleKeys: ['r1technician', 'r2technician'],
        ),
        AttendanceColumn(
          label: 'Human player',
          roleKeys: ['r1humanPlayer', 'r2humanPlayer'],
        ),
      ],
    ),
    AttendanceView(
      label: 'Robot 1',
      columns: [
        AttendanceColumn(label: 'Driver', roleKeys: ['r1driver']),
        AttendanceColumn(label: 'Operator', roleKeys: ['r1operator']),
        AttendanceColumn(label: 'Technician', roleKeys: ['r1technician']),
        AttendanceColumn(label: 'Human player', roleKeys: ['r1humanPlayer']),
      ],
    ),
    AttendanceView(
      label: 'Robot 2',
      columns: [
        AttendanceColumn(label: 'Driver', roleKeys: ['r2driver']),
        AttendanceColumn(label: 'Operator', roleKeys: ['r2operator']),
        AttendanceColumn(label: 'Technician', roleKeys: ['r2technician']),
        AttendanceColumn(label: 'Human player', roleKeys: ['r2humanPlayer']),
      ],
    ),
  ],
);

const List<ScheduleConfig> scheduleConfigs = [
  singleRobotConfig,
  twoRobotConfig,
];

class DriverSchedule {
  DriverSchedule({
    required this.config,
    required this.slots,
    required this.handoff,
    required Map<String, List<String>> columns,
    required Map<String, Set<String>> rosters,
  }) : _columns = columns,
       _rosters = rosters;

  final ScheduleConfig config;

  final int slots;

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
      for (var slot = 0; slot < slots - 1; slot++) {
        final nextDriver = schedule.nameAt(pair.driver, slot + 1);
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
    final columns = view.columns;
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
