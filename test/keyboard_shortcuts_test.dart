import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/widgets/keyboard_shortcuts.dart';

/// #197: the desktop build had no keyboard path at all, which all four platform
/// guidelines require. These cover the shortcut widgets plus the Escape
/// behaviour that comes free, so the assumption is on record.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ctrl+S and Cmd+S both save', (tester) async {
    var saves = 0;
    await _pump(
      tester,
      SaveShortcut(
        onSave: () => saves++,
        child: const TextField(autofocus: true),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(saves, 2);
  });

  testWidgets('a plain S does not save, so typing is safe', (tester) async {
    var saves = 0;
    await _pump(
      tester,
      SaveShortcut(
        onSave: () => saves++,
        child: const TextField(autofocus: true),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();

    expect(saves, 0);
  });

  testWidgets('a null onSave leaves the child alone', (tester) async {
    await _pump(tester, const SaveShortcut(onSave: null, child: Text('form')));

    expect(find.byType(CallbackShortcuts), findsNothing);
    expect(find.text('form'), findsOneWidget);
  });

  testWidgets('left and right arrows step through a row', (tester) async {
    final List<String> steps = <String>[];
    await _pump(
      tester,
      HorizontalStepShortcuts(
        onPrevious: () => steps.add('previous'),
        onNext: () => steps.add('next'),
        child: TextButton(
          autofocus: true,
          onPressed: () {},
          child: const Text('Lab'),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(steps, <String>['next', 'previous']);
  });

  testWidgets('Escape closes a modal bottom sheet', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => const SizedBox(height: 120, child: Text('editor')),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('editor'), findsNothing);
  });
}
