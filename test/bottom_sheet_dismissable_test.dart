import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a scroll-controlled sheet is dismissable', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      var index = source.indexOf('showModalBottomSheet');
      while (index != -1) {
        final end = source.indexOf('builder:', index);
        final call = end == -1
            ? source.substring(index)
            : source.substring(index, end);
        if (call.contains('isScrollControlled: true') &&
            !call.contains('showDragHandle: true')) {
          final line = '\n'.allMatches(source.substring(0, index)).length + 1;
          offenders.add('${file.path}:$line');
        }
        index = source.indexOf('showModalBottomSheet', index + 1);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These sheets can grow to full height, which takes the drag away '
          'from the sheet and leaves no barrier to tap, so there is no way '
          'out of them without a drag handle (#292):\n${offenders.join('\n')}',
    );
  });
}
