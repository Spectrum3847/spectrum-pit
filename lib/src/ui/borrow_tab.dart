import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/borrow_record.dart';
import '../state/borrow_controller.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';

class BorrowTab extends StatefulWidget {
  const BorrowTab({required this.controller, super.key});

  final BorrowController controller;

  @override
  State<BorrowTab> createState() => _BorrowTabState();
}

class _BorrowTabState extends State<BorrowTab> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final items = _sorted(widget.controller.items);
        return Stack(
          children: [
            items.isEmpty
                ? _EmptyBoard(onAdd: () => _openEditor())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _BorrowRow(
                      record: items[i],
                      onTap: () => _openEditor(record: items[i]),
                      onCheckIn: items[i].returned
                          ? null
                          : () => _checkIn(items[i]),
                    ),
                  ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: null,
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Check out tool'),
              ),
            ),
          ],
        );
      },
    );
  }

  List<BorrowRecord> _sorted(List<BorrowRecord> items) {
    return [
      for (final r in items)
        if (!r.returned) r,
      for (final r in items)
        if (r.returned) r,
    ];
  }

  Future<void> _checkIn(BorrowRecord record) {
    return widget.controller
        .upsert(
          record.copyWith(
            returned: true,
            checkedInAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        )
        .catchError((Object error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not check in "${record.toolName}": $error'),
            ),
          );
        });
  }

  Future<void> _openEditor({BorrowRecord? record}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _BorrowEditorSheet(
        record: record,
        onSubmit: (result) {
          widget.controller.upsert(result).catchError((Object error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not save "${result.toolName}": $error'),
              ),
            );
          });
          Navigator.of(sheetContext).pop();
        },
        onDelete: record == null
            ? null
            : () async {
                final confirmed = await _confirmDelete(
                  sheetContext,
                  record.toolName,
                );
                if (!confirmed) return;
                await widget.controller.delete(record.id).catchError((
                  Object error,
                ) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Could not delete "${record.toolName}": $error',
                      ),
                    ),
                  );
                });
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String toolName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete borrow record?'),
        content: Text(
          'Remove the loan record for "$toolName". This cannot be undone.',
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
}

class _BorrowRow extends StatelessWidget {
  const _BorrowRow({required this.record, required this.onTap, this.onCheckIn});

  final BorrowRecord record;
  final VoidCallback onTap;
  final VoidCallback? onCheckIn;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = record.isOverdueAt(now);
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
              border: Border.all(
                color: overdue
                    ? PitPalette.statusOverdueOf(context)
                    : PitPalette.outlineOf(context),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.toolName,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              _TeamLabel(
                                name: record.teamName,
                                number: record.teamNumber,
                              ),
                              if (record.competition.isNotEmpty)
                                _CompetitionLabel(name: record.competition),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (onCheckIn != null)
                      FilledButton.tonal(
                        onPressed: onCheckIn,
                        child: const Text('Check in'),
                      ),
                    if (record.returned)
                      _ReturnedChip()
                    else if (overdue)
                      const _OverdueChip(),
                  ],
                ),
                const SizedBox(height: 8),
                _Timestamps(record: record),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamLabel extends StatelessWidget {
  const _TeamLabel({required this.name, required this.number});

  final String name;
  final int number;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Team',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: muted),
        ),
        const SizedBox(width: 6),
        Text(
          number.toString(),
          style: pitCodeStyle(context, color: PitPalette.inkOf(context)),
        ),
        if (name.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            name,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}

class _CompetitionLabel extends StatelessWidget {
  const _CompetitionLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events_outlined, size: 14, color: muted),
        const SizedBox(width: 4),
        Text(
          name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
        ),
      ],
    );
  }
}

class _Timestamps extends StatelessWidget {
  const _Timestamps({required this.record});

  final BorrowRecord record;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final fmt = _shortDateTime;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _TimestampLabel(
          label: 'Out',
          value: fmt(record.checkedOutAt),
          color: muted,
        ),
        if (record.estimatedReturn != null)
          _TimestampLabel(
            label: 'Expected',
            value: fmt(record.estimatedReturn!),
            color: muted,
          ),
        if (record.checkedInAt != null)
          _TimestampLabel(
            label: 'In',
            value: fmt(record.checkedInAt!),
            color: muted,
          ),
      ],
    );
  }
}

class _TimestampLabel extends StatelessWidget {
  const _TimestampLabel({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
        const SizedBox(width: 6),
        Text(value, style: pitCodeStyle(context, color: color)),
      ],
    );
  }
}

class _ReturnedChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = PitPalette.statusReadyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            'Returned',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _OverdueChip extends StatelessWidget {
  const _OverdueChip();

  @override
  Widget build(BuildContext context) {
    final color = PitPalette.statusOverdueOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            'Overdue',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
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
                Icon(Icons.handshake_outlined, size: 40, color: muted),
                const SizedBox(height: 12),
                Text(
                  'No tools on loan',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Check out a tool to another team to start tracking.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Check out tool'),
                ),
              ],
            ),
          ),
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

String _shortDateTime(DateTime dt) {
  final local = dt.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$m/$d $h:$min';
}

class _BorrowEditorSheet extends StatefulWidget {
  const _BorrowEditorSheet({
    required this.record,
    required this.onSubmit,
    this.onDelete,
  });

  final BorrowRecord? record;
  final ValueChanged<BorrowRecord> onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<_BorrowEditorSheet> createState() => _BorrowEditorSheetState();
}

class _BorrowEditorSheetState extends State<_BorrowEditorSheet> {
  late final TextEditingController _toolName;
  late final TextEditingController _teamName;
  late final TextEditingController _teamNumber;
  late final TextEditingController _competition;
  late DateTime _checkedOutAt;
  DateTime? _estimatedReturn;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _toolName = TextEditingController(text: record?.toolName ?? '');
    _teamName = TextEditingController(text: record?.teamName ?? '');
    _teamNumber = TextEditingController(
      text: record?.teamNumber.toString() ?? '',
    );
    _competition = TextEditingController(text: record?.competition ?? '');
    _checkedOutAt = record?.checkedOutAt ?? DateTime.now().toUtc();
    _estimatedReturn = record?.estimatedReturn;
  }

  @override
  void dispose() {
    _toolName.dispose();
    _teamName.dispose();
    _teamNumber.dispose();
    _competition.dispose();
    super.dispose();
  }

  void _save() {
    final toolName = _toolName.text.trim();
    if (toolName.isEmpty) return;
    final teamNumber = int.tryParse(_teamNumber.text.trim()) ?? 0;
    final existing = widget.record;
    widget.onSubmit(
      BorrowRecord(
        id: existing?.id ?? const Uuid().v4(),
        itemId: existing?.itemId,
        toolName: toolName,
        teamName: _teamName.text.trim(),
        teamNumber: teamNumber,
        competition: _competition.text.trim(),
        checkedOutAt: _checkedOutAt,
        estimatedReturn: _estimatedReturn,
        checkedInAt: existing?.checkedInAt,
        returned: existing?.returned ?? false,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _pickCheckoutDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1);
    final lastDate = DateTime(now.year + 1);

    final checkedOutLocal = _checkedOutAt.toLocal();
    final clamped = checkedOutLocal.isBefore(firstDate)
        ? firstDate
        : checkedOutLocal.isAfter(lastDate)
        ? lastDate
        : checkedOutLocal;
    final date = await showDatePicker(
      context: context,
      initialDate: clamped,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(checkedOutLocal),
    );

    if (!mounted) return;
    setState(() {
      _checkedOutAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? checkedOutLocal.hour,
        time?.minute ?? checkedOutLocal.minute,
      ).toUtc();
    });
  }

  Future<void> _pickEstimatedReturn() async {
    final now = DateTime.now();
    final firstDate = now;
    final lastDate = DateTime(now.year + 1);

    final initial = (_estimatedReturn ?? now.add(const Duration(days: 1)))
        .toLocal();
    final clamped = initial.isBefore(firstDate)
        ? firstDate
        : initial.isAfter(lastDate)
        ? lastDate
        : initial;
    final date = await showDatePicker(
      context: context,
      initialDate: clamped,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date == null) return;
    if (!mounted) return;
    final base = _estimatedReturn ?? now.add(const Duration(hours: 2));
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base.toLocal()),
    );
    if (!mounted) return;
    setState(() {
      _estimatedReturn = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 17,
        time?.minute ?? 0,
      ).toUtc();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.record != null;
    final muted = PitPalette.inkMutedOf(context);
    return Padding(
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
                    editing ? 'Edit loan' : 'Check out tool',
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
              controller: _toolName,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Tool name',
                hintText: 'Cordless drill',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _teamName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Team name',
                hintText: 'The Cheesy Poofs',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _teamNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Team number',
                hintText: '254',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _competition,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Competition',
                hintText: 'Texas State Championship',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Checkout time',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: muted),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickCheckoutDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_shortDateTime(_checkedOutAt)),
            ),
            const SizedBox(height: 12),
            Text(
              'Estimated return (optional)',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: muted),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickEstimatedReturn,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                _estimatedReturn != null
                    ? _shortDateTime(_estimatedReturn!)
                    : 'Set date',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _toolName.text.trim().isEmpty ? null : _save,
              child: Text(editing ? 'Save' : 'Check out'),
            ),
          ],
        ),
      ),
    );
  }
}
