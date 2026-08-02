import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/user_profile.dart';
import '../models/user_role.dart';
import 'user_role_service.dart';

class DesktopUserRoleService implements UserRoleService {
  DesktopUserRoleService({
    required fc.Firestore firestore,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _firestore = firestore,
       _pollInterval = pollInterval;

  final fc.Firestore _firestore;
  final Duration _pollInterval;

  @override
  Future<Set<UserRole>> fetchOrCreateRoles({
    required String uid,
    String displayName = '',
    String? email,
  }) async {
    try {
      final doc = await _firestore.getDocument('userProfiles/$uid');
      if (doc == null) {
        try {
          await _firestore.createDocument('userProfiles', <String, dynamic>{
            'uid': uid,
            'displayName': displayName,
            'email': ?email,
            'roles': ['viewer'],
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }, id: uid);
        } catch (_) {}
        return {UserRole.viewer};
      }
      return UserProfile.fromJson(uid, doc.fields).roles;
    } catch (_) {
      return {UserRole.viewer};
    }
  }

  @override
  Future<void> updateRoles(String targetUid, Set<UserRole> roles) async {
    await _firestore.setDocument(
      'userProfiles/$targetUid',
      <String, dynamic>{'roles': roles.map((r) => r.name).toList()},
      updateMask: const ['roles'],
    );
  }

  @override
  Stream<List<UserProfile>> streamAllProfiles() async* {
    String? last;
    while (true) {
      List<UserProfile>? profiles;
      try {
        final docs = await _firestore.listDocuments('userProfiles');
        profiles =
            docs.map((d) => UserProfile.fromJson(d.id, d.fields)).toList()
              ..sort(
                (a, b) => a.displayName.toLowerCase().compareTo(
                  b.displayName.toLowerCase(),
                ),
              );
      } catch (_) {
        if (last == null) {
          rethrow;
        }
      }
      if (profiles != null) {
        final fingerprint = profiles
            .map(
              (p) =>
                  '${p.uid}:'
                  '${(p.roles.map((r) => r.name).toList()..sort()).join(',')}:'
                  '${p.displayName}',
            )
            .join('|');
        if (fingerprint != last) {
          last = fingerprint;
          yield profiles;
        }
      }
      await Future<void>.delayed(_pollInterval);
    }
  }
}
