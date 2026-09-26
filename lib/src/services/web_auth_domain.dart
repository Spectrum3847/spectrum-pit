import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const Set<String> ownHostingDomains = {
  'spectrumpit.web.app',
  'spectrumpit-staging.web.app',
  'spectrumpit-preview.web.app',
  'spectrumpit.firebaseapp.com',
  'spectrumpit-staging.firebaseapp.com',
  'spectrumpit-preview.firebaseapp.com',
};

FirebaseOptions webFirebaseOptionsForHost(
  String host,
  FirebaseOptions defaults,
) {
  if (!ownHostingDomains.contains(host)) {
    return defaults;
  }
  return defaults.copyWith(authDomain: host);
}
