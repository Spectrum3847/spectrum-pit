import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/pit_shift.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../services/spectrum_auth_service.dart';
import '../state/pit_shift_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';
import '../widgets/keyboard_shortcuts.dart';
import 'driver_schedule_screen.dart';

class ScheduleTab extends StatefulWidget {
  const ScheduleTab({
    required this.controller,
    required this.authService,
    required this.roleController,
    super.key,
  });

  final PitShiftController controller;
  final SpectrumAuthService authService;

  final UserRoleController roleController;

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  String? _competition;
  bool _mineOnly = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final competitions = _competitions();
        final competition = _selectedCompetition(competitions);
        return Stack(
          children: [
            competition == null
                ? _EmptySchedule(
                    onAdd: () => _openEditor(),
                    onDriverSchedule: _openDriverSchedule,
                  )
                : _buildSchedule(context, competitions, competition),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: null,
                onPressed: () => _openEditor(competition: competition),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add shift'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSchedule(
    BuildContext context,
    List<String> competitions,
    String competition,
  ) {
    final uid = widget.authService.currentUser?.uid;
    final shifts = widget.controller.shiftsForCompetition(competition);
    final conflicts = widget.controller.conflicts
        .where((c) => c.first.competition == competition)
        .toList();

    final rows = _mineOnly
        ? shifts
              .where((s) => uid != null && s.assignedUids.contains(uid))
              .toList()
        : shifts;
    final shownConflicts = _mineOnly
        ? conflicts.where((c) => uid != null && _involves(c, uid)).toList()
        : conflicts;

    final conflictIds = <String>{
      for (final conflict in shownConflicts) ...[
        conflict.first.id,
        conflict.second.id,
      ],
    };

    return Column(
      children: [
        _ScheduleHeader(
          competitions: competitions,
          competition: competition,
          mineOnly: _mineOnly,
          canMarkUnavailable: uid != null,
          onCompetitionChanged: (next) => setState(() => _competition = next),
          onMineOnlyChanged: (next) => setState(() => _mineOnly = next),
          onMarkUnavailable: () =>
              _openEditor(competition: competition, unavailable: true),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _DriverScheduleEntry(onOpen: _openDriverSchedule),
              if (shownConflicts.isNotEmpty)
                _ConflictPanel(conflicts: shownConflicts),
              if (rows.isEmpty)
                _EmptyRows(
                  mineOnly: _mineOnly,
                  signedIn: uid != null,
                  competition: competition,
                  onAdd: () => _openEditor(competition: competition),
                  onMarkUnavailable: () =>
                      _openEditor(competition: competition, unavailable: true),
                )
              else
                for (final shift in rows)
                  _ShiftRow(
                    shift: shift,
                    conflicted: conflictIds.contains(shift.id),
                    onTap: () => _openEditor(shift: shift),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  List<String> _competitions() {
    final names = <String>{
      for (final shift in widget.controller.items)
        if (shift.competition.isNotEmpty) shift.competition,
    }.toList();
    names.sort();
    return names;
  }

  String? _selectedCompetition(List<String> competitions) {
    final picked = _competition;
    if (picked != null && competitions.contains(picked)) return picked;
    return competitions.isEmpty ? null : competitions.first;
  }

  static bool _involves(PitShiftConflict conflict, String uid) =>
      conflict.first.assignedUids.contains(uid) &&
      conflict.second.assignedUids.contains(uid);

  void _openDriverSchedule() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DriverScheduleScreen(
          knownPeople: _knownAssignees(),
          rosterStream: widget.roleController.streamAllProfiles(),

          shiftController: widget.controller,
          competition: _selectedCompetition(_competitions()),
        ),
      ),
    );
  }

  Map<String, String> _knownAssignees() {
    final known = <String, String>{};
    for (final shift in widget.controller.items) {
      for (var i = 0; i < shift.assignedUids.length; i++) {
        final name = i < shift.assignedNames.length
            ? shift.assignedNames[i].trim()
            : '';
        if (name.isEmpty) continue;
        known[shift.assignedUids[i]] = name;
      }
    }
    final user = widget.authService.currentUser;
    if (user != null) known[user.uid] = _displayNameOf(user);
    return known;
  }

  Future<void> _openEditor({
    PitShift? shift,
    String? competition,
    bool unavailable = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,

      showDragHandle: true,
      builder: (sheetContext) => _ShiftEditorSheet(
        shift: shift,
        unavailable: unavailable,
        competition: shift?.competition ?? competition ?? '',
        currentUser: widget.authService.currentUser,
        knownAssignees: _knownAssignees(),
        rosterStream: widget.roleController.streamAllProfiles(),
        onSubmit: (result) {
          widget.controller
              .upsert(result)
              .catchError(
                (Object error) =>
                    _showSyncError('save "${result.label}"', error),
              );
          Navigator.of(sheetContext).pop();
        },
        onDelete: shift == null
            ? null
            : () async {
                final confirmed = await _confirmDelete(sheetContext, shift);
                if (!confirmed) return;
                try {
                  await widget.controller.delete(shift.id);
                } catch (error) {
                  _showSyncError('delete "${shift.label}"', error);
                  return;
                }
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, PitShift shift) async {
    final unavailable = shift.kind == ShiftKind.unavailable;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(unavailable ? 'Remove this block?' : 'Delete shift?'),
        content: Text(
          unavailable
              ? 'Remove "${shift.label}" so this time counts as available '
                    'again. This cannot be undone.'
              : 'Remove "${shift.label}" from the schedule. This cannot be '
                    'undone.',
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
            child: Text(unavailable ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _showSyncError(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not $action: $error')));
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.competitions,
    required this.competition,
    required this.mineOnly,
    required this.canMarkUnavailable,
    required this.onCompetitionChanged,
    required this.onMineOnlyChanged,
    required this.onMarkUnavailable,
  });

  final List<String> competitions;
  final String competition;
  final bool mineOnly;
  final bool canMarkUnavailable;
  final ValueChanged<String> onCompetitionChanged;
  final ValueChanged<bool> onMineOnlyChanged;
  final VoidCallback onMarkUnavailable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (competitions.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: competition,
              decoration: const InputDecoration(labelText: 'Competition'),
              items: [
                for (final name in competitions)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) {
                if (value != null) onCompetitionChanged(value);
              },
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Everyone')),
                  ButtonSegment(value: true, label: Text('Mine')),
                ],
                selected: {mineOnly},
                onSelectionChanged: (s) => onMineOnlyChanged(s.first),
              ),
              if (canMarkUnavailable)
                OutlinedButton.icon(
                  onPressed: onMarkUnavailable,
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Mark unavailable'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConflictPanel extends StatelessWidget {
  const _ConflictPanel({required this.conflicts});

  final List<PitShiftConflict> conflicts;

  @override
  Widget build(BuildContext context) {
    final alert = _overdueOf(context);
    final count = conflicts.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alert.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        border: Border.all(color: alert),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: alert),
              const SizedBox(width: 8),
              Text(
                count == 1 ? '1 conflict' : '$count conflicts',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: alert),
              ),
            ],
          ),
          for (final conflict in conflicts) ...[
            const SizedBox(height: 8),
            _ConflictLine(conflict: conflict),
          ],
        ],
      ),
    );
  }
}

class _ConflictLine extends StatelessWidget {
  const _ConflictLine({required this.conflict});

  final PitShiftConflict conflict;

  @override
  Widget build(BuildContext context) {
    final unavailableSecond =
        conflict.first.kind == ShiftKind.unavailable &&
        conflict.second.kind != ShiftKind.unavailable;
    final booked = unavailableSecond ? conflict.second : conflict.first;
    final other = unavailableSecond ? conflict.first : conflict.second;
    final againstUnavailable = other.kind == ShiftKind.unavailable;

    final ink = PitPalette.inkOf(context);
    final body = Theme.of(context).textTheme.bodyMedium?.copyWith(color: ink);
    final code = pitCodeStyle(context, color: ink);
    return Text.rich(
      TextSpan(
        style: body,
        children: [
          TextSpan(
            text: _sharedNames(conflict),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: ': '),
          TextSpan(text: '"${_labelOf(booked)}" '),
          TextSpan(text: _rangeLabel(booked), style: code),
          TextSpan(
            text: againstUnavailable
                ? ' falls in unavailable time '
                : ' overlaps ',
          ),
          TextSpan(text: '"${_labelOf(other)}" '),
          TextSpan(text: _rangeLabel(other), style: code),
        ],
      ),
    );
  }

  static String _sharedNames(PitShiftConflict conflict) {
    final names = <String>[];
    final first = conflict.first;
    for (var i = 0; i < first.assignedUids.length; i++) {
      final uid = first.assignedUids[i];
      if (!conflict.second.assignedUids.contains(uid)) continue;
      final name = i < first.assignedNames.length ? first.assignedNames[i] : '';
      names.add(name.isEmpty ? uid : name);
    }
    return names.isEmpty ? 'Someone' : names.join(', ');
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({
    required this.shift,
    required this.conflicted,
    required this.onTap,
  });

  final PitShift shift;
  final bool conflicted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final alert = _overdueOf(context);
    final names = shift.assignedNames
        .where((n) => n.trim().isNotEmpty)
        .toList();
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
                color: conflicted ? alert : PitPalette.outlineOf(context),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _labelOf(shift),
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _KindChip(kind: shift.kind),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      _rangeLabel(shift),
                      style: pitCodeStyle(context, color: muted),
                    ),
                    if (names.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          names.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: muted),
                        ),
                      ),
                    ],
                  ],
                ),
                if (conflicted) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: alert),
                      const SizedBox(width: 6),
                      Text(
                        'Conflict',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: alert),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final ShiftKind kind;

  @override
  Widget build(BuildContext context) {
    final neutral = kind == ShiftKind.unavailable;
    final fg = neutral
        ? PitPalette.inkMutedOf(context)
        : _kindColor(context, kind);
    final border = neutral ? PitPalette.outlineOf(context) : fg;
    final bg = neutral
        ? PitPalette.surfaceStrongOf(context)
        : fg.withValues(alpha: 0.2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_kindIcon(kind), size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            _kindLabel(kind),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule({required this.onAdd, required this.onDriverSchedule});

  final VoidCallback onAdd;
  final VoidCallback onDriverSchedule;

  @override
  Widget build(BuildContext context) {
    return _Slot(
      icon: Icons.event_note_outlined,
      title: 'No shifts scheduled',
      body: 'Add the first shift to start building the pit schedule.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add shift'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onDriverSchedule,
            icon: const Icon(Icons.sports_score_outlined),
            label: const Text('Driver schedule'),
          ),
        ],
      ),
    );
  }
}

class _DriverScheduleEntry extends StatelessWidget {
  const _DriverScheduleEntry({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: PitPalette.surfaceOf(context),
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(PitPalette.radiusSm),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PitPalette.radiusSm),
              border: Border.all(color: PitPalette.outlineOf(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.sports_score_outlined, color: muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver schedule',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Generate a balanced match rotation for drivers, '
                        'operators, technicians, and human players.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRows extends StatelessWidget {
  const _EmptyRows({
    required this.mineOnly,
    required this.signedIn,
    required this.competition,
    required this.onAdd,
    required this.onMarkUnavailable,
  });

  final bool mineOnly;
  final bool signedIn;
  final String competition;
  final VoidCallback onAdd;
  final VoidCallback onMarkUnavailable;

  @override
  Widget build(BuildContext context) {
    if (mineOnly && !signedIn) {
      return const _Slot(
        icon: Icons.person_outline_rounded,
        title: 'Not signed in',
        body: 'Sign in to see what you are on for.',
      );
    }
    if (mineOnly) {
      return _Slot(
        icon: Icons.person_outline_rounded,
        title: 'You are not on the schedule',
        body: 'Nothing at $competition is assigned to you yet.',
        action: OutlinedButton.icon(
          onPressed: onMarkUnavailable,
          icon: const Icon(Icons.event_busy_outlined),
          label: const Text('Mark unavailable'),
        ),
      );
    }
    return _Slot(
      icon: Icons.event_note_outlined,
      title: 'Nothing scheduled yet',
      body: 'Add a shift for $competition.',
      action: FilledButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add shift'),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

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
                Icon(icon, size: 40, color: muted),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: muted),
                ),
                if (action != null) ...[const SizedBox(height: 16), action!],
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

enum _RangeMode { match, time }

class _ShiftEditorSheet extends StatefulWidget {
  const _ShiftEditorSheet({
    required this.shift,
    required this.unavailable,
    required this.competition,
    required this.currentUser,
    required this.knownAssignees,
    required this.rosterStream,
    required this.onSubmit,
    this.onDelete,
  });

  final PitShift? shift;
  final bool unavailable;
  final String competition;
  final SpectrumUser? currentUser;
  final Map<String, String> knownAssignees;
  final Stream<List<UserProfile>> rosterStream;
  final ValueChanged<PitShift> onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<_ShiftEditorSheet> createState() => _ShiftEditorSheetState();
}

class _ShiftEditorSheetState extends State<_ShiftEditorSheet> {
  late final TextEditingController _label;
  late final TextEditingController _competition;
  late final TextEditingController _startMatch;
  late final TextEditingController _endMatch;
  late final TextEditingController _notes;
  late ShiftKind _kind;
  late _RangeMode _mode;
  late Map<String, String> _selected;
  DateTime? _startsAt;
  DateTime? _endsAt;

  bool get _selfOnly => widget.unavailable;

  @override
  void initState() {
    super.initState();
    final shift = widget.shift;
    _label = TextEditingController(text: shift?.label ?? '');
    _competition = TextEditingController(
      text: shift?.competition ?? widget.competition,
    );
    _startMatch = TextEditingController(
      text: shift?.startMatch?.toString() ?? '',
    );
    _endMatch = TextEditingController(text: shift?.endMatch?.toString() ?? '');
    _notes = TextEditingController(text: shift?.notes ?? '');
    _kind =
        shift?.kind ??
        (widget.unavailable ? ShiftKind.unavailable : ShiftKind.matchBlock);
    _startsAt = shift?.startsAt;
    _endsAt = shift?.endsAt;
    if (shift != null) {
      _mode = shift.hasTimeRange && !shift.hasMatchRange
          ? _RangeMode.time
          : _RangeMode.match;
    } else {
      _mode = widget.unavailable ? _RangeMode.time : _RangeMode.match;
    }
    _selected = _initialAssignees();
  }

  Map<String, String> _initialAssignees() {
    final shift = widget.shift;
    if (shift != null && !_selfOnly) {
      return {
        for (var i = 0; i < shift.assignedUids.length; i++)
          shift.assignedUids[i]: i < shift.assignedNames.length
              ? shift.assignedNames[i]
              : shift.assignedUids[i],
      };
    }
    final user = widget.currentUser;
    if (user == null) return <String, String>{};
    return {user.uid: _displayNameOf(user)};
  }

  @override
  void dispose() {
    _label.dispose();
    _competition.dispose();
    _startMatch.dispose();
    _endMatch.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _rangeSet => switch (_mode) {
    _RangeMode.match =>
      int.tryParse(_startMatch.text.trim()) != null ||
          int.tryParse(_endMatch.text.trim()) != null,
    _RangeMode.time => _startsAt != null || _endsAt != null,
  };

  bool get _rangeValid => switch (_mode) {
    _RangeMode.match => _matchRangeValid,
    _RangeMode.time => _timeRangeValid,
  };

  bool get _matchRangeValid {
    final start = int.tryParse(_startMatch.text.trim());
    final end = int.tryParse(_endMatch.text.trim());
    if (start == null || end == null) return true;
    return start <= end;
  }

  bool get _timeRangeValid {
    final start = _startsAt;
    final end = _endsAt;
    if (start == null || end == null) return true;
    return !start.isAfter(end);
  }

  bool get _canSave =>
      _label.text.trim().isNotEmpty &&
      _competition.text.trim().isNotEmpty &&
      _selected.isNotEmpty &&
      _rangeSet &&
      _rangeValid;

  void _save() {
    if (!_canSave) return;
    final byMatch = _mode == _RangeMode.match;
    final existing = widget.shift;
    final uids = _selected.keys.toList(growable: false);
    widget.onSubmit(
      PitShift(
        id: existing?.id ?? const Uuid().v4(),
        label: _label.text.trim(),
        kind: _kind,
        competition: _competition.text.trim(),
        assignedUids: uids,
        assignedNames: [for (final uid in uids) _selected[uid] ?? uid],
        startMatch: byMatch ? int.tryParse(_startMatch.text.trim()) : null,
        endMatch: byMatch ? int.tryParse(_endMatch.text.trim()) : null,
        startsAt: byMatch ? null : _startsAt,
        endsAt: byMatch ? null : _endsAt,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _pickBound({required bool start}) async {
    final now = DateTime.now();
    final current = (start ? _startsAt : _endsAt)?.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? current?.hour ?? 8,
      time?.minute ?? current?.minute ?? 0,
    ).toUtc();
    setState(() {
      if (start) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final editing = widget.shift != null;
    final title = _selfOnly
        ? 'Mark yourself unavailable'
        : editing
        ? 'Edit shift'
        : 'Add shift';

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
                      title,
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
              if (_selfOnly) ...[
                const SizedBox(height: 4),
                Text(
                  'Nobody else is changed. The crew sees this time as yours, and '
                  'anything scheduled over it is flagged.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                autofocus: !editing,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _selfOnly ? 'Reason' : 'Shift name',
                  hintText: _selfOnly ? 'Driving home' : 'Pit duty, qual block',
                ),
              ),
              if (!_selfOnly) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<ShiftKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final kind in ShiftKind.values)
                      if (kind != ShiftKind.unavailable)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(_kindLabel(kind)),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _kind = value);
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _competition,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Competition',
                  hintText: 'Texas State Championship',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Scheduled by',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: muted),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_RangeMode>(
                segments: const [
                  ButtonSegment(
                    value: _RangeMode.match,
                    label: Text('Match'),
                    icon: Icon(Icons.sports_score_outlined),
                  ),
                  ButtonSegment(
                    value: _RangeMode.time,
                    label: Text('Time'),
                    icon: Icon(Icons.schedule_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                _mode == _RangeMode.match
                    ? 'Match numbers only. Clock times are ignored.'
                    : 'Clock times only. Match numbers are ignored.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              if (_mode == _RangeMode.match)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startMatch,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'First match',
                          hintText: '18',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endMatch,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Last match',
                          hintText: '34',
                        ),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickBound(start: true),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: Text(
                        _startsAt == null
                            ? 'Set start'
                            : 'Starts ${_shortDateTime(_startsAt!.toLocal())}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _pickBound(start: false),
                      icon: const Icon(Icons.stop_outlined),
                      label: Text(
                        _endsAt == null
                            ? 'Set end'
                            : 'Ends ${_shortDateTime(_endsAt!.toLocal())}',
                      ),
                    ),
                  ],
                ),
              if (!_selfOnly) ...[
                const SizedBox(height: 16),
                Text(
                  'Assigned to',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: muted),
                ),
                const SizedBox(height: 8),
                _AssigneePicker(
                  known: widget.knownAssignees,
                  rosterStream: widget.rosterStream,
                  selected: _selected,
                  onChanged: (next) => setState(() => _selected = next),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Bring the spare battery cart',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _canSave ? _save : null,
                child: Text(
                  _selfOnly
                      ? (editing ? 'Save' : 'Mark unavailable')
                      : (editing ? 'Save' : 'Add shift'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssigneePicker extends StatelessWidget {
  const _AssigneePicker({
    required this.known,
    required this.rosterStream,
    required this.selected,
    required this.onChanged,
  });

  final Map<String, String> known;
  final Stream<List<UserProfile>> rosterStream;
  final Map<String, String> selected;
  final ValueChanged<Map<String, String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserProfile>>(
      stream: rosterStream,
      builder: (context, snapshot) {
        final candidates = <String, String>{
          for (final profile in snapshot.data ?? const <UserProfile>[])
            if (profile.roles.isMember)
              profile.uid: profile.displayName.trim().isEmpty
                  ? (profile.email ?? profile.uid)
                  : profile.displayName.trim(),
          ...selected,
          ...known,
        };
        final uids = candidates.keys.toList()
          ..sort((a, b) => candidates[a]!.compareTo(candidates[b]!));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final uid in uids)
                  FilterChip(
                    label: Text(candidates[uid]!),
                    selected: selected.containsKey(uid),

                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    onSelected: (on) {
                      final next = Map<String, String>.of(selected);
                      if (on) {
                        next[uid] = candidates[uid]!;
                      } else {
                        next.remove(uid);
                      }
                      onChanged(next);
                    },
                  ),
              ],
            ),
            if (snapshot.hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Only people already on the schedule are listed. Ask an admin '
                'to add anyone missing.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: PitPalette.inkMutedOf(context)),
              ),
            ],
          ],
        );
      },
    );
  }
}

String _labelOf(PitShift shift) =>
    shift.label.trim().isEmpty ? 'Untitled shift' : shift.label.trim();

String _displayNameOf(SpectrumUser user) => user.displayName.trim().isEmpty
    ? (user.email ?? user.uid)
    : user.displayName.trim();

String _kindLabel(ShiftKind kind) => switch (kind) {
  ShiftKind.loadIn => 'Load in',
  ShiftKind.matchBlock => 'Match block',
  ShiftKind.pitDuty => 'Pit duty',
  ShiftKind.loadOut => 'Load out',
  ShiftKind.unavailable => 'Unavailable',
};

IconData _kindIcon(ShiftKind kind) => switch (kind) {
  ShiftKind.loadIn => Icons.move_to_inbox_outlined,
  ShiftKind.matchBlock => Icons.sports_score_outlined,
  ShiftKind.pitDuty => Icons.build_outlined,
  ShiftKind.loadOut => Icons.local_shipping_outlined,
  ShiftKind.unavailable => Icons.event_busy_outlined,
};

Color _kindColor(BuildContext context, ShiftKind kind) {
  return switch (kind) {
    ShiftKind.loadIn => PitPalette.statusStagingOf(context),
    ShiftKind.matchBlock => PitPalette.statusReadyOf(context),
    ShiftKind.pitDuty => PitPalette.statusLoadingOf(context),
    ShiftKind.loadOut => PitPalette.statusPackingOf(context),
    ShiftKind.unavailable => PitPalette.inkMutedOf(context),
  };
}

Color _overdueOf(BuildContext context) => PitPalette.statusOverdueOf(context);

String _rangeLabel(PitShift shift) {
  if (shift.hasMatchRange) {
    final start = shift.startMatch;
    final end = shift.endMatch;
    if (start != null && end != null) {
      return start == end ? 'M$start' : 'M$start-M$end';
    }
    return start != null ? 'M$start-' : '-M$end';
  }
  if (shift.hasTimeRange) {
    final start = shift.startsAt?.toLocal();
    final end = shift.endsAt?.toLocal();
    if (start != null && end != null) {
      final sameDay =
          start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      return sameDay
          ? '${_shortDateTime(start)}-${_timeOnly(end)}'
          : '${_shortDateTime(start)}-${_shortDateTime(end)}';
    }
    return start != null
        ? '${_shortDateTime(start)}-'
        : '-${_shortDateTime(end!)}';
  }
  return 'NO TIME';
}

String _shortDateTime(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$m/$d ${_timeOnly(dt)}';
}

String _timeOnly(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
