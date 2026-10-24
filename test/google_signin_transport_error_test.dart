// ignore_for_file: invalid_use_of_protected_member

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';

void main() {
  test('canceled does not fall back', () {
    expect(
      isGoogleSignInTransportError(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      ),
      isFalse,
    );
  });

  test('interrupted does not fall back', () {
    expect(
      isGoogleSignInTransportError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.interrupted,
        ),
      ),
      isFalse,
    );
  });

  test('unknownError, the missing-Play-services case, falls back', () {
    expect(
      isGoogleSignInTransportError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
      ),
      isTrue,
    );
  });

  test('clientConfigurationError falls back', () {
    expect(
      isGoogleSignInTransportError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      ),
      isTrue,
    );
  });

  test('providerConfigurationError falls back', () {
    expect(
      isGoogleSignInTransportError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.providerConfigurationError,
        ),
      ),
      isTrue,
    );
  });

  test('uiUnavailable falls back', () {
    expect(
      isGoogleSignInTransportError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.uiUnavailable,
        ),
      ),
      isTrue,
    );
  });

  test('userMismatch falls back', () {
    expect(
      isGoogleSignInTransportError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.userMismatch,
        ),
      ),
      isTrue,
    );
  });

  test('a non-GoogleSignInException does not fall back', () {
    expect(isGoogleSignInTransportError(StateError('boom')), isFalse);
  });
}
