import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory_item.dart';
import '../state/inventory_controller.dart';
import '../theme/pit_palette.dart';
import 'location_code.dart';

Future<InventoryItem?> showItemJump(
  BuildContext context, {
  required InventoryController controller,
}) {
  return showDialog<InventoryItem>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Find a tool'),

      content: SizedBox(
        width: 480,
        child: _ItemJumpBody(items: controller.items),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class ItemJumpShortcut extends StatefulWidget {
  const ItemJumpShortcut({
    required this.onJump,
    required this.child,
    this.enabled,
    super.key,
  });

  final ValueChanged<BuildContext> onJump;
  final Widget child;
  final bool? enabled;

  @override
  State<ItemJumpShortcut> createState() => _ItemJumpShortcutState();
}

class _ItemJumpShortcutState extends State<ItemJumpShortcut> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  bool get _typing {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return false;
    if (focus.widget is EditableText) return true;
    return focus.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.slash) return false;
    if (!(widget.enabled ?? _isDesktop)) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? false) || _typing) {
      return false;
    }
    widget.onJump(context);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _statusLabel(InventoryStatus status) => switch (status) {
  InventoryStatus.inLab => 'In Lab',
  InventoryStatus.inPit => 'In Pit',
  InventoryStatus.borrowed => 'Borrowed',
};

class _ItemJumpBody extends StatefulWidget {
  const _ItemJumpBody({required this.items});

  final List<InventoryItem> items;

  @override
  State<_ItemJumpBody> createState() => _ItemJumpBodyState();
}

class _ItemJumpBodyState extends State<_ItemJumpBody> {
  String _query = '';

  List<InventoryItem> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items
        .where(
          (i) =>
              i.name.toLowerCase().contains(q) ||
              i.labLocation.toLowerCase().contains(q) ||
              i.pitLocation.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return SizedBox(
      width: double.maxFinite,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.go,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (matches.isNotEmpty) {
                  Navigator.of(context).pop(matches.first);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Tool name or location',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No matching tools',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: PitPalette.inkMutedOf(context)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      itemBuilder: (context, i) => _ItemRow(
                        item: matches[i],
                        onTap: () => Navigator.of(context).pop(matches[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: item.name, style: text.bodyLarge),
                    TextSpan(
                      text: '  ${_statusLabel(item.status)}',
                      style: text.labelMedium?.copyWith(
                        color: PitPalette.inkMutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 16,
                children: [
                  LocationCode(label: 'Lab', code: item.labLocation),
                  LocationCode(label: 'Pit', code: item.pitLocation),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
