import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/web_cache_reset.dart';

void main() {
  test('is a no-op off web', () async {
    await expectLater(clearCachedBuild(), completes);
  });
}
