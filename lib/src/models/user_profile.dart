import 'user_role.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.email,
    required this.roles,
  });

  final String uid;
  final String displayName;
  final String? email;

  final Set<UserRole> roles;

  factory UserProfile.fromJson(String uid, Map<String, dynamic> data) {
    final Set<UserRole> roles;
    final rolesField = data['roles'];
    if (rolesField is List && rolesField.isNotEmpty) {
      final parsed = rolesField
          .whereType<String>()
          .map(UserRole.tryParse)
          .whereType<UserRole>()
          .toSet();
      roles = parsed.isEmpty ? {UserRole.viewer} : parsed;
    } else {
      roles = {UserRole.fromString(data['role'] as String?)};
    }
    return UserProfile(
      uid: uid,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String?,
      roles: roles,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'displayName': displayName,
    if (email != null) 'email': email,
    'roles': roles.map((r) => r.name).toList(),
  };
}
