import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class SpectrumUser {
  const SpectrumUser({
    required this.uid,
    required this.displayName,
    this.email,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? email;
  final String? photoUrl;
}

enum SpectrumAuthState { signedOut, signingIn, signedIn, error }

class SpectrumAuthSnapshot {
  const SpectrumAuthSnapshot({required this.state, this.user, this.error});

  final SpectrumAuthState state;
  final SpectrumUser? user;
  final String? error;
}

abstract class SpectrumAuthService {
  Stream<SpectrumAuthSnapshot> get snapshotStream;
  SpectrumAuthSnapshot get snapshot;
  SpectrumUser? get currentUser;

  Future<String?> idToken();

  Future<void> initialize();
  Future<void> signIn();
  Future<void> signOut();
  Future<void> dispose();
}

class FirebaseSpectrumAuthService implements SpectrumAuthService {
  FirebaseSpectrumAuthService({
    FirebaseAuth? appAuth,
    GoogleSignIn? googleSignIn,
  }) : _appAuth = appAuth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _appAuth;
  final GoogleSignIn _googleSignIn;

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();
  SpectrumAuthSnapshot _snapshot = const SpectrumAuthSnapshot(
    state: SpectrumAuthState.signedOut,
  );
  StreamSubscription<User?>? _authStateSubscription;

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _snapshot.user;

  @override
  Future<String?> idToken() async => _appAuth.currentUser?.getIdToken();

  @override
  Future<void> initialize() async {
    if (!kIsWeb) {
      await _googleSignIn.initialize();
    }
    _authStateSubscription = _appAuth.authStateChanges().listen((user) {
      if (user == null) {
        if (_snapshot.state != SpectrumAuthState.signingIn) {
          _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
        }
      } else {
        _emit(
          SpectrumAuthSnapshot(
            state: SpectrumAuthState.signedIn,
            user: _userFrom(user),
          ),
        );
      }
    });
    final existing = _appAuth.currentUser;
    if (existing != null) {
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.signedIn,
          user: _userFrom(existing),
        ),
      );
    } else {
      _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
    }
  }

  @override
  Future<void> signIn() async {
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signingIn));
    try {
      final UserCredential result;
      if (kIsWeb) {
        result = await _appAuth.signInWithPopup(GoogleAuthProvider());
      } else {
        final account = await _googleSignIn.authenticate();
        final auth = account.authentication;
        final idToken = auth.idToken;
        if (idToken == null) {
          throw StateError('Google sign-in returned no ID token.');
        }
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        result = await _appAuth.signInWithCredential(credential);
      }
      final user = result.user;
      if (user == null) {
        throw StateError('Firebase sign-in returned no user.');
      }
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.signedIn,
          user: _userFrom(user),
        ),
      );
    } catch (error) {
      debugPrint('Sign-in failed: $error');
      _emit(
        SpectrumAuthSnapshot(
          state: SpectrumAuthState.error,
          error: _friendlyAuthError(error),
        ),
      );
    }
  }

  static String _friendlyAuthError(Object error) {
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled) {
      return 'Sign-in was cancelled.';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return 'Network error. Check your connection and try again.';
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
        case 'user-cancelled':
          return 'Sign-in was cancelled.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with a different sign-in method.';
        case 'operation-not-allowed':
          return 'Google sign-in is not enabled for this app.';
        case 'unauthorized-domain':
          return 'This site is not authorized for sign-in. Contact an admin.';
      }
    }
    return 'Sign-in failed. Please try again.';
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }
    try {
      await _appAuth.signOut();
    } catch (_) {}
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
  }

  @override
  Future<void> dispose() async {
    await _authStateSubscription?.cancel();
    await _controller.close();
  }

  SpectrumUser _userFrom(User user) {
    return SpectrumUser(
      uid: user.uid,
      displayName: user.displayName ?? '',
      email: user.email,
      photoUrl: user.photoURL,
    );
  }

  void _emit(SpectrumAuthSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }
}
