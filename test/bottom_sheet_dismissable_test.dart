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
      final source = _withoutStringLiterals(file.readAsStringSync());
      var index = source.indexOf('showModalBottomSheet');
      while (index != -1) {
        final call = _callAt(source, index);
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

String _callAt(String source, int start) {
  final open = source.indexOf('(', start);
  if (open == -1) return source.substring(start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return source.substring(start);
}

String _withoutStringLiterals(String source) {
  final out = StringBuffer();
  String? quote;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote == null) {
      if (char == "'" || char == '"') quote = char;
      out.write(char);
      continue;
    }
    if (char == r'\' && i + 1 < source.length) {
      out.write('  ');
      i++;
      continue;
    }
    if (char == quote || char == '\n') {
      quote = null;
      out.write(char);
      continue;
    }
    out.write(' ');
  }
  return out.toString();
}
