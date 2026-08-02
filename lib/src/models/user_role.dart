enum UserRole {
  viewer,

  pit,

  admin,

  developer;

  static final Map<String, UserRole> _byName = {
    for (final role in UserRole.values) role.name: role,
  };

  static UserRole fromString(String? value) =>
      tryParse(value) ?? UserRole.viewer;

  static UserRole? tryParse(String? value) =>
      value == null ? null : _byName[value];

  String get displayName {
    switch (this) {
      case UserRole.viewer:
        return 'Viewer';
      case UserRole.pit:
        return 'Pit';
      case UserRole.admin:
        return 'Admin';
      case UserRole.developer:
        return 'Developer';
    }
  }

  bool get isDebug => this == UserRole.developer;

  bool get canManageUsers => this == UserRole.admin;
}

extension UserRoleSetPermissions on Set<UserRole> {
  List<int> get visibleTabIndices {
    final tabs = <int>{};
    for (final role in this) {
      switch (role) {
        case UserRole.viewer:
          break;
        case UserRole.pit:
        case UserRole.developer:
          tabs.addAll(const [0, 1, 2, 3, 4, 5, 7]);
        case UserRole.admin:
          tabs.addAll(const [0, 1, 2, 3, 4, 5, 6, 7]);
      }
    }
    return tabs.toList()..sort();
  }

  bool get isMember => any((r) => r != UserRole.viewer);

  bool get canManageUsers => any((r) => r.canManageUsers);

  bool get isDebug => any((r) => r.isDebug);

  String get displayText {
    final names = map((r) => r.displayName).toList()..sort();
    return names.join(', ');
  }
}
