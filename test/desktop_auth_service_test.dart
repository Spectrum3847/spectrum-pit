import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/services/desktop_auth_service.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';

/// A mocked Identity Toolkit + Secure Token backend.
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

DesktopAuthService _service({int refreshStatus = 200}) {
  return DesktopAuthService(
    clientId: 'client-123',
    firebaseApiKey: 'fake-key',
    session: fc.FirebaseAuthSession(
      apiKey: 'fake-key',
      httpClient: _firebaseBackend(refreshStatus: refreshStatus),
    ),
    signInFlow: () async => const fc.GoogleTokens(idToken: 'google-id-token'),
  );
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
    await service.signIn();

    expect(service.snapshot.state, SpectrumAuthState.error);
    expect(service.snapshot.error, 'Sign-in was cancelled or denied.');
  });
}
