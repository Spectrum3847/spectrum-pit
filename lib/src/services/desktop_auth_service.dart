import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:shared_preferences/shared_preferences.dart';

import 'spectrum_auth_service.dart';

class DesktopAuthService implements SpectrumAuthService {
  DesktopAuthService({
    required this.clientId,
    required this.firebaseApiKey,
    this.clientSecret = '',
    Future<void> Function(Uri url)? launch,
    fc.FirebaseAuthSession? session,
    Future<fc.GoogleTokens> Function()? signInFlow,
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _session = session ?? fc.FirebaseAuthSession(apiKey: firebaseApiKey),
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance {
    _signInFlow =
        signInFlow ??
        () => fc.GoogleDesktopOAuth(
          clientId: clientId,
          clientSecret: clientSecret,
          launcher: launch ?? _noLauncher,
        ).signIn();
  }

  static const String _prefsKey = 'desktop_auth_session_v1';

  final String clientId;
  final String firebaseApiKey;

  final String clientSecret;

  final fc.FirebaseAuthSession _session;
  final Future<SharedPreferences> Function() _prefsLoader;
  late final Future<fc.GoogleTokens> Function() _signInFlow;

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();
  SpectrumAuthSnapshot _snapshot = const SpectrumAuthSnapshot(
    state: SpectrumAuthState.signedOut,
  );

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _snapshot.user;

  @override
  Future<String?> idToken() => _session.getIdToken();

  @override
  Future<void> initialize() async {
    try {
      final prefs = await _prefsLoader();
      final stored = prefs.getString(_prefsKey);
      if (stored == null) return;
      final user = await _session.restore(
        (jsonDecode(stored) as Map).cast<String, dynamic>(),
      );
      if (user != null) {
        _emit(
          SpectrumAuthSnapshot(
            state: SpectrumAuthState.signedIn,
            user: _toSpectrumUser(user),
          ),
        );
      } else {
        await prefs.remove(_prefsKey);
      }
    } catch (_) {}
  }

  @override
  Future<void> signIn() async {
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signingIn));
    try {
      final tokens = await _signInFlow();
      final user = await _session.signInWithGoogleIdToken(tokens.idToken);
      final prefs = await _prefsLoader();

      await prefs.setString(_prefsKey, jsonEncode(_session.toJson()));
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.signedIn,
          user: _toSpectrumUser(user),
        ),
      );
    } catch (error) {
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: _friendly(error),
        ),
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _session.signOut();
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefsKey);
    } catch (_) {}
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
    _session.close();
  }

  static SpectrumUser _toSpectrumUser(fc.FirebaseUser user) => SpectrumUser(
    uid: user.uid,
    displayName: user.displayName,
    email: user.email,
    photoUrl: user.photoUrl,
  );

  static Future<void> _noLauncher(Uri url) async {
    throw UnsupportedError('No URL launcher was provided.');
  }

  String _friendly(Object error) {
    if (error is StateError) return error.message;
    if (error is fc.FirebaseAuthException) {
      return 'Sign-in failed (${error.message}).';
    }
    if (error is SocketException) {
      return 'Could not reach Google or Firebase. Check your connection.';
    }
    return 'Sign-in failed. Please try again.';
  }

  void _emit(SpectrumAuthSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}
