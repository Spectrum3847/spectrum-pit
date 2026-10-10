// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCrgWATJGoXkkVSGgO3uizS5gAyK3KBdN4',
    appId: '1:883337539000:web:926cdd9e8204e13f22334d',
    messagingSenderId: '883337539000',
    projectId: 'spectrumpit',
    authDomain: 'spectrumpit.firebaseapp.com',
    storageBucket: 'spectrumpit.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBtAJaftV1ADzq1OF8Z0cdC4gQkWTO46Gc',
    appId: '1:883337539000:android:c45a3d6f0c67c4fc22334d',
    messagingSenderId: '883337539000',
    projectId: 'spectrumpit',
    storageBucket: 'spectrumpit.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDKppYL5KEZkMIvCPO0yQxpUpxjcsRyEqg',
    appId: '1:883337539000:ios:db45763db6c8674122334d',
    messagingSenderId: '883337539000',
    projectId: 'spectrumpit',
    storageBucket: 'spectrumpit.firebasestorage.app',
    iosClientId: '883337539000-vhmpbs3ue69k5bnh627ajvicv1v3mfrn.apps.googleusercontent.com',
    iosBundleId: 'org.spectrum3847.spectrumpit',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDKppYL5KEZkMIvCPO0yQxpUpxjcsRyEqg',
    appId: '1:883337539000:ios:db45763db6c8674122334d',
    messagingSenderId: '883337539000',
    projectId: 'spectrumpit',
    storageBucket: 'spectrumpit.firebasestorage.app',
    iosClientId: '883337539000-vhmpbs3ue69k5bnh627ajvicv1v3mfrn.apps.googleusercontent.com',
    iosBundleId: 'org.spectrum3847.spectrumpit',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCrgWATJGoXkkVSGgO3uizS5gAyK3KBdN4',
    appId: '1:883337539000:web:926cdd9e8204e13f22334d',
    messagingSenderId: '883337539000',
    projectId: 'spectrumpit',
    authDomain: 'spectrumpit.firebaseapp.com',
    storageBucket: 'spectrumpit.firebasestorage.app',
  );
}
