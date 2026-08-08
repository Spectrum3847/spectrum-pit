import 'dart:async';

import 'package:spectrumpit/src/services/spectrum_auth_service.dart';

class FakeSpectrumAuthService implements SpectrumAuthService {
  FakeSpectrumAuthService({SpectrumUser? initialUser}) {
    _snapshot = SpectrumAuthSnapshot(
      state: initialUser == null
          ? SpectrumAuthState.signedOut
          : SpectrumAuthState.signedIn,
      user: initialUser,
    );
  }

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();
  SpectrumAuthSnapshot _snapshot = const SpectrumAuthSnapshot(
    state: SpectrumAuthState.signedOut,
  );

  int initializeCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;

  SpectrumUser nextSignInUser = const SpectrumUser(
    uid: 'test-uid',
    displayName: 'Test User',
    email: 'test@example.com',
  );

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _snapshot.user;

  String? nextIdToken = 'fake-id-token';

  @override
  Future<String?> idToken() async =>
      _snapshot.state == SpectrumAuthState.signedIn ? nextIdToken : null;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> signIn() async {
    signInCalls++;
    _emit(
      SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: nextSignInUser,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
  }

  void emit(SpectrumAuthSnapshot next) => _emit(next);

  void _emit(SpectrumAuthSnapshot next) {
    _snapshot = next;
    _controller.add(next);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
