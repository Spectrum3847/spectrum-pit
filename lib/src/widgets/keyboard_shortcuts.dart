library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SaveShortcut extends StatelessWidget {
  const SaveShortcut({required this.onSave, required this.child, super.key});

  final VoidCallback? onSave;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onSave = this.onSave;
    if (onSave == null) return child;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
      },
      child: child,
    );
  }
}
