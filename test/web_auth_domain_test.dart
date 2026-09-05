import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/web_auth_domain.dart';

void main() {
  const defaults = FirebaseOptions(
    apiKey: 'key',
    appId: 'app',
    messagingSenderId: 'sender',
    projectId: 'spectrumpit',
    authDomain: 'spectrumpit.firebaseapp.com',
  );

  test('overrides authDomain for the staging web.app host', () {
    final result = webFirebaseOptionsForHost(
      'spectrumpit-staging.web.app',
      defaults,
    );
    expect(result.authDomain, 'spectrumpit-staging.web.app');
  });

  test('overrides authDomain for the prod web.app host', () {
    final result = webFirebaseOptionsForHost('spectrumpit.web.app', defaults);
    expect(result.authDomain, 'spectrumpit.web.app');
  });

  test('overrides authDomain for the default firebaseapp.com host', () {
    final result = webFirebaseOptionsForHost(
      'spectrumpit.firebaseapp.com',
      defaults,
    );
    expect(result.authDomain, 'spectrumpit.firebaseapp.com');
  });

  test('overrides authDomain for the staging firebaseapp.com host', () {
    final result = webFirebaseOptionsForHost(
      'spectrumpit-staging.firebaseapp.com',
      defaults,
    );
    expect(result.authDomain, 'spectrumpit-staging.firebaseapp.com');
  });

  test('overrides authDomain for the fixed preview site host', () {
    final result = webFirebaseOptionsForHost(
      'spectrumpit-preview.web.app',
      defaults,
    );
    expect(result.authDomain, 'spectrumpit-preview.web.app');
  });

  test('leaves authDomain alone for a hosting preview channel host', () {
    final result = webFirebaseOptionsForHost(
      'spectrumpit--pr-321-324-xv3713mi.web.app',
      defaults,
    );
    expect(result.authDomain, defaults.authDomain);
  });

  test('leaves authDomain alone for an unrelated host', () {
    final result = webFirebaseOptionsForHost(
      'spectrum3847.github.io',
      defaults,
    );
    expect(result.authDomain, defaults.authDomain);
  });

  test('leaves authDomain alone for localhost', () {
    final result = webFirebaseOptionsForHost('localhost', defaults);
    expect(result.authDomain, defaults.authDomain);
  });

  test('other fields are unchanged when the host overrides authDomain', () {
    final result = webFirebaseOptionsForHost('spectrumpit.web.app', defaults);
    expect(result.apiKey, defaults.apiKey);
    expect(result.appId, defaults.appId);
    expect(result.messagingSenderId, defaults.messagingSenderId);
    expect(result.projectId, defaults.projectId);
  });
}
