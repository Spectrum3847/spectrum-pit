import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/services/desktop_auth_service.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';

MockClient _firebaseBackend({int refreshStatus = 200}) {
  return MockClient((request) async {
    if (request.url.host == 'securetoken.googleapis.com') {
      if (refreshStatus != 200) {
        return http.Response('{"error":"revoked"}', refreshStatus);
      }
      return http.Response(
        jsonEncode({
          'id_token': 'fb-token-refreshed',
          'refresh_token': 'refresh-2',
          'expires_in': '3600',
        }),
        200,
      );
    }
    expect(request.url.path, contains('accounts:signInWithIdp'));
    return http.Response(
      jsonEncode({
        'localId': 'uid-9',
        'idToken': 'fb-token-1',
        'refreshToken': 'refresh-1',
        'expiresIn': '3600',
        'displayName': 'Dana Scout',
        'email': 'dana@example.com',
      }),
      200,
    );
  });
}

class _ThrowingSignOutSession extends fc.FirebaseAuthSession {
  _ThrowingSignOutSession({required super.apiKey, required super.httpClient});

  @override
  Future<void> signOut() async {
    throw const SocketException('sign-out unreachable');
  }
}

DesktopAuthService _service({int refreshStatus = 200}) {
  final service = DesktopAuthService(
    clientId: 'client-123',
    firebaseApiKey: 'fake-key',
    session: fc.FirebaseAuthSession(
      apiKey: 'fake-key',
      httpClient: _firebaseBackend(refreshStatus: refreshStatus),
    ),
    signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('signIn exchanges the Google token and emits signedIn', () async {
    final service = _service();
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    expect(service.currentUser?.uid, 'uid-9');
    expect(service.currentUser?.displayName, 'Dana Scout');
    expect(await service.idToken(), 'fb-token-1');
  });

  test(
    'snapshotStream emits signingIn then signedIn on a successful sign-in',
    () async {
      final service = _service();
      final states = <SpectrumAuthState>[];
      final sub = service.snapshotStream.listen((s) => states.add(s.state));
      addTearDown(sub.cancel);

      await service.signIn();

      await Future<void>.delayed(Duration.zero);

      expect(
        states,
        containsAllInOrder(<SpectrumAuthState>[
          SpectrumAuthState.signingIn,
          SpectrumAuthState.signedIn,
        ]),
      );
    },
  );

  test('signIn persists the session for the next launch', () async {
    await _service().signIn();

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('desktop_auth_session_v1');
    expect(stored, isNotNull);
    final decoded = jsonDecode(stored!) as Map<String, dynamic>;
    expect(decoded['uid'], 'uid-9');
    expect(decoded['refreshToken'], 'refresh-1');
  });

  test('initialize restores a persisted session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v1': jsonEncode({
        'uid': 'uid-9',
        'displayName': 'Dana Scout',
        'email': 'dana@example.com',
        'refreshToken': 'refresh-1',
      }),
    });
    final service = _service();
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    expect(service.currentUser?.uid, 'uid-9');
    expect(await service.idToken(), 'fb-token-refreshed');
  });

  test('initialize drops a revoked session and stays signed out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v1': jsonEncode({
        'uid': 'uid-9',
        'refreshToken': 'dead',
      }),
    });
    final service = _service(refreshStatus: 400);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNull);
  });

  test('signOut clears the session and the persisted copy', () async {
    final service = _service();
    await service.signIn();
    await service.signOut();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(await service.idToken(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNull);
  });

  test('signOut drops the data scoped to the user who left', () async {
    final service = _service();
    final ended = <String>[];
    service.onSessionEnded = (uid) async => ended.add(uid);
    await service.signIn();
    await service.signOut();

    expect(ended, <String>['uid-9']);
  });

  test('signOut completes when clearing the cached data fails', () async {
    final service = _service();
    service.onSessionEnded = (_) async =>
        throw const FileSystemException('locked');
    await service.signIn();
    await service.signOut();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNull);
  });

  test('a revoked session drops the data cached for it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v1': jsonEncode({
        'uid': 'uid-gone',
        'refreshToken': 'dead',
      }),
    });
    final service = _service(refreshStatus: 400);
    final ended = <String>[];
    service.onSessionEnded = (uid) async => ended.add(uid);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(ended, <String>['uid-gone']);
  });

  test('initialize drops a payload with a wrong-typed refresh token', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v1': jsonEncode({
        'uid': 'uid-9',
        'refreshToken': 12345,
      }),
    });
    final service = _service();
    final ended = <String>[];
    service.onSessionEnded = (uid) async => ended.add(uid);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNull);

    expect(ended, <String>['uid-9']);
  });

  test('initialize stays signed in when the network fails', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v1': jsonEncode({
        'uid': 'uid-9',
        'refreshToken': 'refresh-1',
      }),
    });
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'fake-key',
      session: fc.FirebaseAuthSession(
        apiKey: 'fake-key',
        httpClient: MockClient(
          (_) async => throw const SocketException('No route to host'),
        ),
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
    );
    addTearDown(service.dispose);
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    expect(service.currentUser?.uid, 'uid-9');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNotNull);

    expect(await service.idToken(), isNull);
  });

  test('initialize drops a corrupt stored payload', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'desktop_auth_session_v1': 'not json at all',
    });
    final service = _service();
    await service.initialize();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNull);
  });

  test('a refresh refused mid-session signs the app out', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final endedFor = <String>[];
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'fake-key',
      session: fc.FirebaseAuthSession(
        apiKey: 'fake-key',
        httpClient: _firebaseBackend(refreshStatus: 403),
        clock: () => now,
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
    );
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await service.initialize();
    await service.signIn();
    expect(service.snapshot.state, SpectrumAuthState.signedIn);

    now = now.add(const Duration(hours: 2));
    expect(await service.idToken(), isNull);

    await pumpEventQueue();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(endedFor, <String>['uid-9']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNull);
  });

  test('signOut tears the session down exactly once', () async {
    final endedFor = <String>[];
    final service = _service();
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await service.initialize();
    await service.signIn();
    await service.signOut();
    await pumpEventQueue();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(endedFor, <String>['uid-9']);
  });

  test('a sign-out that throws still ends the session', () async {
    final endedFor = <String>[];
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'fake-key',
      session: _ThrowingSignOutSession(
        apiKey: 'fake-key',
        httpClient: _firebaseBackend(),
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
    );
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await service.initialize();
    await service.signIn();
    await service.signOut();
    await pumpEventQueue();

    expect(service.snapshot.state, SpectrumAuthState.signedOut);
    expect(endedFor, <String>['uid-9']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNull);
  });

  test('the service still works after a sign-out that threw', () async {
    final endedFor = <String>[];
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'fake-key',
      session: _ThrowingSignOutSession(
        apiKey: 'fake-key',
        httpClient: _firebaseBackend(),
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
    );
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await service.initialize();
    await service.signIn();
    await service.signOut();
    await pumpEventQueue();

    await service.signIn();
    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNotNull);
  });

  test('overlapping initialize calls leave one live subscription', () async {
    final endedFor = <String>[];
    var now = DateTime.utc(2026, 1, 1, 12);
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'fake-key',
      session: fc.FirebaseAuthSession(
        apiKey: 'fake-key',
        httpClient: _firebaseBackend(refreshStatus: 403),
        clock: () => now,
      ),
      signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
    );
    addTearDown(service.dispose);
    service.onSessionEnded = (uid) async => endedFor.add(uid);

    await Future.wait(<Future<void>>[
      service.initialize(),
      service.initialize(),
      service.initialize(),
    ]);
    await service.signIn();

    now = now.add(const Duration(hours: 2));
    expect(await service.idToken(), isNull);
    await pumpEventQueue();

    expect(endedFor, <String>['uid-9']);
  });

  test('signing in during a teardown keeps the new session', () async {
    final releaseCleanup = Completer<void>();
    final service = _service();
    service.onSessionEnded = (_) => releaseCleanup.future;

    await service.initialize();
    await service.signIn();

    final signOut = service.signOut();
    await pumpEventQueue();

    final signIn = service.signIn();
    await pumpEventQueue();
    releaseCleanup.complete();
    await Future.wait(<Future<void>>[signOut, signIn]);

    expect(service.snapshot.state, SpectrumAuthState.signedIn);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('desktop_auth_session_v1'), isNotNull);
  });

  test('a failed sign-in flow emits a friendly error', () async {
    final service = DesktopAuthService(
      clientId: 'client-123',
      firebaseApiKey: 'fake-key',
      session: fc.FirebaseAuthSession(
        apiKey: 'fake-key',
        httpClient: _firebaseBackend(),
      ),
      signInFlow: () async =>
          throw StateError('Sign-in was cancelled or denied.'),
    );
    addTearDown(service.dispose);
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.error);
    expect(service.snapshot.error, 'Sign-in was cancelled or denied.');
  });
}
