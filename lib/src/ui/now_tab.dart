import 'package:flutter/material.dart';

import '../models/borrow_record.dart';
import '../models/now_summary.dart';
import '../models/packing_record.dart';
import '../models/pit_shift.dart';
import '../state/borrow_controller.dart';
import '../state/inventory_controller.dart';
import '../state/packing_controller.dart';
import '../state/pit_shift_controller.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';

const int _maxOverdueShown = 3;

class NowTab extends StatelessWidget {
  const NowTab({
    required this.inventoryController,
    required this.packingController,
    required this.borrowController,
    required this.pitShiftController,
    required this.currentUid,
    required this.onOpenBorrowed,
    required this.onOpenPacking,
    required this.onOpenSchedule,
    this.onJump,
    super.key,
  });

  final InventoryController inventoryController;
  final PackingController packingController;
  final BorrowController borrowController;
  final PitShiftController pitShiftController;
  final String? currentUid;
  final VoidCallback onOpenBorrowed;
  final VoidCallback onOpenPacking;
  final VoidCallback onOpenSchedule;

  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        inventoryController,
        packingController,
        borrowController,
        pitShiftController,
      ]),
      builder: (context, _) {
        final summary = NowSummary.from(
          items: inventoryController.items,
          packing: packingController.items,
          loans: borrowController.items,
          shifts: pitShiftController.items,
          currentUid: currentUid,
          now: DateTime.now(),
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    if (summary.needsAttention)
                      _AttentionCard(
                        summary: summary,
                        onOpenBorrowed: onOpenBorrowed,
                        onOpenSchedule: onOpenSchedule,
                      )
                    else
                      const _QuietLine('Nothing needs attention'),
                    if (onJump != null) _FindToolField(onTap: onJump!),
                    _ShiftsCard(summary: summary, onOpen: onOpenSchedule),
                    _PackingCard(summary: summary, onOpen: onOpenPacking),
                    _LoanCard(summary: summary, onOpen: onOpenBorrowed),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuietLine extends StatelessWidget {
  const _QuietLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: PitPalette.inkMutedOf(context)),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.onTap});

  final String title;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          child,
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.summary,
    required this.onOpenBorrowed,
    required this.onOpenSchedule,
  });

  final NowSummary summary;
  final VoidCallback onOpenBorrowed;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final overdue = summary.overdueLoans;
    final hidden = overdue.length - _maxOverdueShown;
    final conflicts = summary.shiftConflictCount;
    final now = DateTime.now();
    return _Section(
      title: 'Needs attention',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final loan in overdue.take(_maxOverdueShown))
            _AttentionRow(
              onTap: onOpenBorrowed,
              label: 'Overdue',
              title: loan.toolName,
              detail: '${_team(loan)}, ${_late(loan, now)}',
            ),
          if (hidden > 0)
            _AttentionRow(
              onTap: onOpenBorrowed,
              label: 'Overdue',
              title: '$hidden more overdue',
              detail: 'See all on loan',
            ),
          if (conflicts > 0)
            _AttentionRow(
              onTap: onOpenSchedule,
              label: 'Conflict',
              title: conflicts == 1
                  ? '1 shift conflict'
                  : '$conflicts shift conflicts',
              detail: 'Your shifts overlap',
            ),
        ],
      ),
    );
  }

  static String _team(BorrowRecord loan) {
    final name = loan.teamName.trim();
    return name.isEmpty
        ? 'Team ${loan.teamNumber}'
        : '${loan.teamNumber} $name';
  }

  static String _late(BorrowRecord loan, DateTime now) {
    final late = now.difference(loan.estimatedReturn!);
    if (late.inDays >= 1) return '${late.inDays}d late';
    if (late.inHours >= 1) return '${late.inHours}h late';
    return '${late.inMinutes.clamp(1, 59)}m late';
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.onTap,
    required this.label,
    required this.title,
    required this.detail,
  });

  final VoidCallback onTap;
  final String label;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = PitPalette.statusOverdueOf(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: label.toUpperCase(),
                            style: text.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: '  $title', style: text.bodyLarge),
                        ],
                      ),
                    ),
                    Text(
                      detail,
                      style: text.bodySmall?.copyWith(
                        color: PitPalette.inkMutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindToolField extends StatelessWidget {
  const _FindToolField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Semantics(
      button: true,
      label: 'Find a tool',
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                spacing: 12,
                children: [
                  Icon(Icons.search_rounded, color: muted),
                  Expanded(
                    child: Text(
                      'Find a tool',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShiftsCard extends StatelessWidget {
  const _ShiftsCard({required this.summary, required this.onOpen});

  final NowSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final shifts = summary.myShifts;
    return _Section(
      title: 'Your next shifts',
      child: shifts.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(
                  'No upcoming shifts assigned to you',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                OutlinedButton(
                  onPressed: onOpen,
                  child: const Text('Open Schedule'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [for (final shift in shifts) _ShiftRow(shift: shift)],
            ),
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.shift});

  final PitShift shift;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = PitPalette.inkMutedOf(context);
    final range = _range(shift);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(shift.label, style: text.bodyLarge),
        Text.rich(
          TextSpan(
            children: [
              if (shift.competition.isNotEmpty)
                TextSpan(
                  text: shift.competition,
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              if (shift.competition.isNotEmpty && range.isNotEmpty)
                const TextSpan(text: '  '),
              if (range.isNotEmpty)
                TextSpan(text: range, style: pitCodeStyle(context)),
            ],
          ),
        ),
      ],
    );
  }

  static String _range(PitShift shift) {
    final start = shift.startMatch;
    final end = shift.endMatch;
    if (start != null || end != null) {
      if (start != null && end != null) {
        return start == end ? 'Match $start' : 'Matches $start-$end';
      }
      return start != null ? 'From match $start' : 'Until match $end';
    }
    final from = shift.startsAt?.toLocal();
    final to = shift.endsAt?.toLocal();
    if (from != null && to != null) {
      final sameDay =
          from.year == to.year && from.month == to.month && from.day == to.day;
      return sameDay
          ? '${_stamp(from)}-${_clock(to)}'
          : '${_stamp(from)}-${_stamp(to)}';
    }
    if (from != null) return 'From ${_stamp(from)}';
    if (to != null) return 'Until ${_stamp(to)}';
    return '';
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  static String _stamp(DateTime t) =>
      '${t.month.toString().padLeft(2, '0')}/'
      '${t.day.toString().padLeft(2, '0')} ${_clock(t)}';
}

class _PackingCard extends StatelessWidget {
  const _PackingCard({required this.summary, required this.onOpen});

  final NowSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _Section(
      title: 'Packing',
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            '${summary.readyCount} of ${summary.packingTotal} ready',
            style: text.bodyLarge,
          ),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final status in PackingStatus.values)
                _StageCount(
                  status: status,
                  count: summary.packingCounts[status] ?? 0,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StageCount extends StatelessWidget {
  const _StageCount({required this.status, required this.count});

  final PackingStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (label, color) = switch (status) {
      PackingStatus.notStarted => (
        'Not started',
        PitPalette.inkMutedOf(context),
      ),
      PackingStatus.packing => ('Packing', PitPalette.statusPackingOf(context)),
      PackingStatus.staging => ('Staging', PitPalette.statusStagingOf(context)),
      PackingStatus.loading => ('Loading', PitPalette.statusLoadingOf(context)),
      PackingStatus.ready => ('Ready', PitPalette.statusReadyOf(context)),
    };
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          TextSpan(text: '$label $count'),
        ],
      ),
      style: text.bodyMedium,
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.summary, required this.onOpen});

  final NowSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final count = summary.openLoanCount;
    return _Section(
      title: 'On loan',
      onTap: onOpen,
      child: Text(switch (count) {
        0 => 'Nothing on loan',
        1 => '1 tool out on loan',
        _ => '$count tools out on loan',
      }, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}
