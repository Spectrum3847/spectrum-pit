import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/models/user_profile.dart';
import 'package:spectrumpit/src/models/user_role.dart';

UserProfile _profile(String uid, String displayName) => UserProfile(
  uid: uid,
  displayName: displayName,
  roles: const {UserRole.viewer},
);

void main() {
  group('byDisplayName', () {
    test('orders case-insensitively by display name', () {
      final profiles = [
        _profile('u1', 'zoe'),
        _profile('u2', 'Alice'),
        _profile('u3', 'bob'),
      ]..sort(UserProfile.byDisplayName);
      expect(profiles.map((p) => p.uid), ['u2', 'u3', 'u1']);
    });

    test('breaks a display-name tie on uid, whatever the input order', () {
      final ascending = [
        _profile('u1', 'Sam'),
        _profile('u2', 'sam'),
        _profile('u3', 'SAM'),
      ]..sort(UserProfile.byDisplayName);
      final descending = [
        _profile('u3', 'SAM'),
        _profile('u2', 'sam'),
        _profile('u1', 'Sam'),
      ]..sort(UserProfile.byDisplayName);

      expect(ascending.map((p) => p.uid), ['u1', 'u2', 'u3']);
      expect(descending.map((p) => p.uid), ascending.map((p) => p.uid));
    });

    test('keeps profiles with no display name together and first', () {
      final profiles = [
        _profile('u2', 'Alice'),
        _profile('u3', ''),
        _profile('u1', ''),
      ]..sort(UserProfile.byDisplayName);
      expect(profiles.map((p) => p.uid), ['u1', 'u3', 'u2']);
    });
  });
}
