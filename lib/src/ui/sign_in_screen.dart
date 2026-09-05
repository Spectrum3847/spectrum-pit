import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/spectrum_auth_service.dart';
import '../state/user_role_controller.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.authService,
    required this.userRoleController,
    super.key,
  });

  final SpectrumAuthService authService;
  final UserRoleController userRoleController;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  SpectrumAuthService get _auth => widget.authService;
  UserRoleController get _roles => widget.userRoleController;

  @override
  void initState() {
    super.initState();
    _authSubscription = _auth.snapshotStream.listen((_) {
      if (mounted) setState(() {});
    });
    _roles.addListener(_onRoleChanged);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _roles.removeListener(_onRoleChanged);
    super.dispose();
  }

  void _onRoleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    await _auth.signIn();
  }

  Future<void> _signOut() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _auth.snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAccountCard(context, snapshot),
          const SizedBox(height: 16),
          _buildAboutCard(context),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    SpectrumAuthSnapshot snapshot,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._accountBody(context, snapshot),
          ],
        ),
      ),
    );
  }

  List<Widget> _accountBody(
    BuildContext context,
    SpectrumAuthSnapshot snapshot,
  ) {
    switch (snapshot.state) {
      case SpectrumAuthState.signingIn:
        return const [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Signing in...'),
            ],
          ),
        ];
      case SpectrumAuthState.error:
        return [
          Text(
            'Sign-in failed: ${snapshot.error ?? "unknown error"}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Try again'),
          ),
        ];
      case SpectrumAuthState.signedIn:
        final user = snapshot.user;
        if (user == null) {
          return _accountBody(
            context,
            const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut),
          );
        }
        return [
          Text(
            user.displayName.isEmpty
                ? (user.email ?? 'Signed in')
                : user.displayName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (user.email != null)
            Text(user.email!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            'uid: ${user.uid}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Roles: ${_roles.roles.displayText}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ];
      case SpectrumAuthState.signedOut:
        return [
          const Text(
            'Sign in with your team Google account to get access. Access is '
            'granted through Spectrum Tasks: if you are not on the team '
            'roster there yet, ask an admin to approve you before signing '
            'in. Once you have signed in, an admin still needs to grant '
            'your role before any tabs appear. The app keeps working '
            'offline once you have signed in.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in with Google'),
          ),
        ];
    }
  }

  Widget _buildAboutCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'About sign-in',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in with your team Google account (the one approved in '
              'Spectrum Tasks). Once signed in, an admin can grant your '
              'roles from the Users tab; your roles determine which tabs '
              'you can open.',
            ),
          ],
        ),
      ),
    );
  }
}
