import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  Future<void> Function(String uid)? onSessionEnded;

  final String clientId;
  final String firebaseApiKey;

  final String clientSecret;

  final fc.FirebaseAuthSession _session;
  final Future<SharedPreferences> Function() _prefsLoader;
  late final Future<fc.GoogleTokens> Function() _signInFlow;

  StreamSubscription<fc.FirebaseUser?>? _authStateSub;

  Future<void>? _listenerSetup;

  bool _endingSession = false;

  Future<void>? _teardown;

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
  Future<String?> idToken() async {
    try {
      return await _session.getIdToken();
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on HttpException {
      return null;
    }
  }

  Future<void> _ensureAuthStateListener() {
    final previous = _listenerSetup;
    final next = () async {
      try {
        await previous;
        await _authStateSub?.cancel();
        _authStateSub = _session.authStateChanges.listen((user) {
          if (user == null) unawaited(_handleSessionRevoked());
        });
      } catch (error) {
        debugPrint('Desktop auth listener setup failed: $error');
      }
    }();
    _listenerSetup = next;
    return next;
  }

  @override
  Future<void> initialize() async {
    await _ensureAuthStateListener();
    try {
      final prefs = await _prefsLoader();
      final stored = prefs.getString(_prefsKey);
      if (stored == null) return;
      final Map<String, dynamic> payload;
      try {
        payload = (jsonDecode(stored) as Map).cast<String, dynamic>();
      } catch (_) {
        await prefs.remove(_prefsKey);
        return;
      }

      final uid = payload['uid'];
      final refreshToken = payload['refreshToken'];
      if (uid is! String ||
          uid.isEmpty ||
          refreshToken is! String ||
          refreshToken.isEmpty) {
        await prefs.remove(_prefsKey);
        if (uid is String && uid.isNotEmpty) await _endSession(uid);
        return;
      }
      final user = await _session.restore(payload);
      if (user != null) {
        _emit(
          SpectrumAuthSnapshot(
            state: SpectrumAuthState.signedIn,
            user: _toSpectrumUser(user),
          ),
        );
      } else {
        await prefs.remove(_prefsKey);
        await _endSession(uid);
      }
    } catch (error) {
      debugPrint('Desktop session restore failed: $error');
    }
  }

  @override
  Future<void> signIn() async {
    await _teardown;
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
    _endingSession = true;
    final departingUid = currentUser?.uid;
    try {
      await _session.signOut();
    } catch (error) {
      debugPrint('Desktop sign-out could not reach the server: $error');
    }
    await _runTeardown(departingUid);
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
  }

  Future<void> _handleSessionRevoked() async {
    if (_endingSession) return;
    if (_snapshot.state != SpectrumAuthState.signedIn) return;
    final departingUid = currentUser?.uid;
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
    await _runTeardown(departingUid);
  }

  Future<void> _runTeardown(String? uid) {
    _endingSession = true;
    final previous = _teardown;
    late final Future<void> done;
    done = () async {
      try {
        try {
          await previous;
        } catch (_) {}
        await _forgetStoredSession();
        if (uid != null) await _endSession(uid);
      } finally {
        if (identical(_teardown, done)) _endingSession = false;
      }
    }();
    _teardown = done;
    return done;
  }

  Future<void> _forgetStoredSession() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  Future<void> _endSession(String uid) async {
    try {
      await onSessionEnded?.call(uid);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await _listenerSetup;
    await _authStateSub?.cancel();
    _authStateSub = null;
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
