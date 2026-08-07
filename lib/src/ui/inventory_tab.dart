import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/inventory_item.dart';
import '../state/inventory_controller.dart';
import '../theme/pit_palette.dart';
import 'location_code.dart';
import '../widgets/keyboard_shortcuts.dart';

class InventoryTab extends StatefulWidget {
  const InventoryTab({required this.controller, super.key});

  final InventoryController controller;

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<InventoryItem> _filtered(List<InventoryItem> items) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return [
      for (final item in items)
        if (item.name.toLowerCase().contains(q) ||
            item.labLocation.toLowerCase().contains(q) ||
            item.pitLocation.toLowerCase().contains(q))
          item,
    ];
  }

  Future<void> _advance(InventoryItem item) {
    return widget.controller
        .upsert(
          item.copyWith(
            status: _nextStatus(item.status),
            updatedAt: DateTime.now().toUtc(),
          ),
        )
        .catchError(
          (Object error) => _showSyncError('update "${item.name}"', error),
        );
  }

  Future<void> _openEditor({InventoryItem? item}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ItemEditorSheet(
        item: item,
        onSubmit: (result) {
          widget.controller
              .upsert(result)
              .catchError(
                (Object error) =>
                    _showSyncError('save "${result.name}"', error),
              );
          Navigator.of(sheetContext).pop();
        },
        onDelete: item == null
            ? null
            : () async {
                final confirmed = await _confirmDelete(sheetContext, item.name);
                if (!confirmed) return;
                try {
                  await widget.controller.delete(item.id);
                } catch (error) {
                  _showSyncError('delete "${item.name}"', error);
                  return;
                }
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
      ),
    );
  }

  void _showSyncError(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not $action: $error')));
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tool?'),
        content: Text(
          'Remove "$name" from the inventory. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final items = _filtered(widget.controller.items);
        final total = widget.controller.items.length;
        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search tools or locations',
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Clear',
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: total == 0
                      ? _EmptyBoard(onAdd: () => _openEditor())
                      : items.isEmpty
                      ? _NoMatches(query: _query)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _InventoryRow(
                            item: items[i],
                            onTap: () => _openEditor(item: items[i]),
                            onAdvance: () => _advance(items[i]),
                          ),
                        ),
                ),
              ],
            ),
            if (total > 0)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add tool'),
                ),
              ),
          ],
        );
      },
    );
  }
}

InventoryStatus _nextStatus(InventoryStatus status) => switch (status) {
  InventoryStatus.inLab => InventoryStatus.inPit,
  InventoryStatus.inPit => InventoryStatus.borrowed,
  InventoryStatus.borrowed => InventoryStatus.inLab,
};

String _statusLabel(InventoryStatus status) => switch (status) {
  InventoryStatus.inLab => 'In Lab',
  InventoryStatus.inPit => 'In Pit',
  InventoryStatus.borrowed => 'Borrowed',
};

IconData _statusIcon(InventoryStatus status) => switch (status) {
  InventoryStatus.inLab => Icons.home_work_outlined,
  InventoryStatus.inPit => Icons.check_circle_outline,
  InventoryStatus.borrowed => Icons.logout_rounded,
};

Color? _statusColor(BuildContext context, InventoryStatus status) {
  switch (status) {
    case InventoryStatus.inLab:
      return null;
    case InventoryStatus.inPit:
      return PitPalette.statusReadyOf(context);
    case InventoryStatus.borrowed:
      return PitPalette.statusPackingOf(context);
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({
    required this.item,
    required this.onTap,
    required this.onAdvance,
  });

  final InventoryItem item;
  final VoidCallback onTap;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PitPalette.surfaceOf(context),
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PitPalette.radiusSm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PitPalette.radiusSm),
              border: Border.all(color: PitPalette.outlineOf(context)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          LocationCode(label: 'Lab', code: item.labLocation),
                          LocationCode(label: 'Pit', code: item.pitLocation),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _StatusTag(status: item.status, onTap: onAdvance),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status, required this.onTap});

  final InventoryStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    final neutral = color == null;
    final fg = neutral ? PitPalette.inkMutedOf(context) : color;
    final bg = neutral
        ? PitPalette.surfaceStrongOf(context)
        : color.withValues(alpha: 0.2);
    final border = neutral ? PitPalette.outlineOf(context) : color;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(PitPalette.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PitPalette.radiusSm),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_statusIcon(status), size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                _statusLabel(status),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: CustomPaint(
          painter: _DashedRectPainter(
            color: PitPalette.outlineOf(context),
            radius: PitPalette.radiusSm,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 40, color: muted),
                const SizedBox(height: 12),
                Text(
                  'The board is empty',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Every tool gets a home. Add the first one.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add tool'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 36, color: muted),
            const SizedBox(height: 12),
            Text(
              'No tools match "$query"',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}

class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({
    required this.item,
    required this.onSubmit,
    this.onDelete,
  });

  final InventoryItem? item;
  final ValueChanged<InventoryItem> onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _lab;
  late final TextEditingController _pit;
  late final TextEditingController _mapRef;
  late InventoryStatus _status;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _lab = TextEditingController(text: item?.labLocation ?? '');
    _pit = TextEditingController(text: item?.pitLocation ?? '');
    _mapRef = TextEditingController(text: item?.mapRef ?? '');
    _status = item?.status ?? InventoryStatus.inLab;
  }

  @override
  void dispose() {
    _name.dispose();
    _lab.dispose();
    _pit.dispose();
    _mapRef.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final existing = widget.item;
    final map = _mapRef.text.trim();
    widget.onSubmit(
      InventoryItem(
        id: existing?.id ?? const Uuid().v4(),
        name: name,
        labLocation: _lab.text.trim(),
        pitLocation: _pit.text.trim(),
        mapRef: map.isEmpty ? null : map,
        status: _status,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;

    return SaveShortcut(
      onSave: _save,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editing ? 'Edit tool' : 'Add tool',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Delete',
                      onPressed: widget.onDelete,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                autofocus: !editing,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Cordless drill',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lab,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Lab location',
                  hintText: 'RC1-DB',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pit,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Pit location',
                  hintText: 'CAB-A2',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mapRef,
                decoration: const InputDecoration(
                  labelText: 'Map reference (optional)',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Status',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: PitPalette.inkMutedOf(context),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<InventoryStatus>(
                segments: [
                  for (final status in InventoryStatus.values)
                    ButtonSegment<InventoryStatus>(
                      value: status,
                      label: Text(_statusLabel(status)),
                      icon: Icon(_statusIcon(status)),
                    ),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _name.text.trim().isEmpty ? null : _save,
                child: Text(editing ? 'Save' : 'Add tool'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
