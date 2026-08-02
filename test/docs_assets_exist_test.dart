import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lightweight drift guard (#461): every `docs/*.md` asset referenced from
/// `lib/` (the Docs tab list and the in-context DocHelpButton deep-links) must
/// point at a real bundled file, so a renamed or removed manual can't leave a
/// dead in-app link. Runs from the package root under `flutter test`.
void main() {
  test('every docs/*.md asset referenced in lib/ exists', () {
    final referenced = <String>{};
    final pattern = RegExp(r"'(docs/[\w./-]+\.md)'");
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final match in pattern.allMatches(entity.readAsStringSync())) {
        referenced.add(match.group(1)!);
      }
    }

    expect(
      referenced,
      isNotEmpty,
      reason: 'Expected to find bundled doc references in lib/.',
    );
    final missing = referenced.where((p) => !File(p).existsSync()).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason: 'These docs are referenced in lib/ but do not exist: $missing',
    );
  });
}
