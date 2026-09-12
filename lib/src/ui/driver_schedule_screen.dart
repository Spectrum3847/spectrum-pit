import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/driver_schedule.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../services/driver_schedule_generator.dart';
import '../services/driver_schedule_import.dart';
import '../services/driver_schedule_store.dart';
import '../state/pit_shift_controller.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';

class DriverScheduleScreen extends StatefulWidget {
  const DriverScheduleScreen({
    super.key,
    this.generator,
    this.knownPeople = const <String, String>{},
    this.rosterStream,
    this.shiftController,
    this.competition,
    this.store,
  });

  final DriverScheduleGenerator? generator;

  final Map<String, String> knownPeople;

  final Stream<List<UserProfile>>? rosterStream;

  final PitShiftController? shiftController;

  final String? competition;

  final DriverScheduleStore? store;

  @override
  State<DriverScheduleScreen> createState() => _DriverScheduleScreenState();
}

class _DriverScheduleScreenState extends State<DriverScheduleScreen> {
  late final DriverScheduleGenerator _generator =
      widget.generator ?? DriverScheduleGenerator();
  late final DriverScheduleStore _store = widget.store ?? DriverScheduleStore();

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  final Map<String, TextEditingController> _nameControllers = {};
  final TextEditingController _slotsController = TextEditingController(
    text: '6',
  );

  int _modeIndex = 0;
  bool _handoff = false;
  String? _slotsError;
  DriverSchedule? _schedule;

  ScheduleConfig get _config => scheduleConfigs[_modeIndex];

  @override
  void dispose() {
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    _slotsController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String inputKey) =>
      _nameControllers.putIfAbsent(inputKey, TextEditingController.new);

  void _selectMode(int index) {
    if (index == _modeIndex) return;
    setState(() {
      _modeIndex = index;

      _schedule = null;
    });
  }

  void _setHandoff(bool value) {
    setState(() => _handoff = value);

    if (_schedule != null) _generate();
  }

  void _generate() {
    final error = validateSlotCount(_slotsController.text);
    if (error != null) {
      setState(() {
        _slotsError = error;
        _schedule = null;
      });
      return;
    }

    final config = _config;
    final inputs = {
      for (final input in config.inputs)
        input.key: parseNameList(_controllerFor(input.key).text),
    };
    final slots = int.parse(_slotsController.text.trim());
    final schedule = _generator.generate(
      config,
      inputs,
      slots: slots,
      handoff: _handoff,
    );
    setState(() {
      _slotsError = null;
      _schedule = schedule;
    });
    _remember(schedule, inputs);
  }

  void _remember(DriverSchedule schedule, Map<String, List<String>> inputs) {
    final competition = widget.competition;
    if (competition == null || competition.isEmpty) {
      return;
    }
    unawaited(
      _store
          .save(
            competition,
            SavedDriverSchedule(
              mode: schedule.config.label,
              slots: schedule.slots,
              handoff: schedule.handoff,
              inputs: inputs,
              grid: {
                for (final role in schedule.config.roleKeys)
                  role: [
                    for (var slot = 0; slot < schedule.slots; slot++)
                      schedule.nameAt(role, slot),
                  ],
              },
              updatedAt: DateTime.now().toUtc(),
            ),
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _restore() async {
    final competition = widget.competition;
    if (competition == null || competition.isEmpty) {
      return;
    }
    final SavedDriverSchedule? loaded;
    try {
      loaded = await _store.load(competition);
    } catch (error) {
      debugPrint('Could not restore the saved rotation: $error');
      return;
    }
    if (loaded == null || !mounted) {
      return;
    }
    final saved = loaded;
    final index = scheduleConfigs.indexWhere((c) => c.label == saved.mode);
    setState(() {
      if (index != -1) {
        _modeIndex = index;
      }
      _handoff = saved.handoff;
      if (saved.slots > 0) {
        _slotsController.text = '${saved.slots}';
      }
      for (final entry in saved.inputs.entries) {
        _controllerFor(entry.key).text = entry.value.join('\n');
      }

      _schedule = saved.toSchedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final muted = PitPalette.inkMutedOf(context);
    final schedule = _schedule;

    return Scaffold(
      appBar: AppBar(title: const Text('Driver schedule')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Generate a balanced match rotation. Repeat a name to give that '
            'person a bigger share; names listed first pick up any spare '
            'turns.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: [
              for (var index = 0; index < scheduleConfigs.length; index++)
                ButtonSegment<int>(
                  value: index,
                  label: Text(scheduleConfigs[index].label),
                ),
            ],
            selected: {_modeIndex},
            onSelectionChanged: (selection) => _selectMode(selection.first),
          ),
          const SizedBox(height: 20),
          ..._nameFields(context, config),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: TextField(
                  controller: _slotsController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _generate(),
                  decoration: InputDecoration(
                    labelText: 'Matches',
                    errorText: _slotsError,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('Generate'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _handoff,
            onChanged: _setHandoff,
            title: const Text('Next driver operates first'),
            subtitle: Text(
              'Each match is operated by whoever drives the match after it.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: muted),
            ),
          ),
          const SizedBox(height: 20),
          if (schedule != null) _ScheduleOutput(schedule: schedule),
          if (schedule != null && !schedule.isEmpty && _canImport) ...[
            const SizedBox(height: 8),
            _ImportAction(
              busy: _importing,
              competition: widget.competition!,
              onImport: () => _import(schedule),
            ),
          ],
        ],
      ),
    );
  }

  bool _importing = false;

  bool get _canImport =>
      widget.shiftController != null &&
      (widget.competition?.isNotEmpty ?? false);

  Future<void> _import(DriverSchedule schedule) async {
    final controller = widget.shiftController;
    final competition = widget.competition;
    if (controller == null || competition == null || competition.isEmpty) {
      return;
    }

    final previous = DriverScheduleImport.previousImports(
      controller.items,
      competition,
    );
    var replace = false;
    if (previous.isNotEmpty) {
      final choice = await _askReplaceOrAdd(previous.length);
      if (choice == null) return;
      replace = choice;
    }

    final uidByName = {
      for (final entry in widget.knownPeople.entries)
        if (entry.value.trim().isNotEmpty) entry.value: entry.key,
    };

    final now = DateTime.now().toUtc();
    final shifts = DriverScheduleImport.toShifts(
      schedule: schedule,
      competition: competition,
      uidByName: uidByName,

      idPrefix: 'drv-${now.millisecondsSinceEpoch}',
      now: now,
    );
    if (shifts.isEmpty) {
      _say('Nothing to import: no name is assigned to any match.');
      return;
    }

    setState(() => _importing = true);
    try {
      await DriverScheduleImport.commit(
        shifts: shifts,
        previous: previous,
        replace: replace,
        upsert: controller.upsert,
        delete: controller.delete,
      );
      _say(
        DriverScheduleImport.summaryOf(
          shifts,
          competition: competition,
          replace: replace,
        ),
      );
    } catch (error) {
      _say('Import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool?> _askReplaceOrAdd(int existing) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Already imported'),
      content: Text(
        '$existing shift${existing == 1 ? '' : 's'} on this schedule came '
        'from a previous import. Replace them, or add these alongside?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Add alongside'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPeoplePicker(ScheduleInput input) {
    final controller = _controllerFor(input.key);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,

      showDragHandle: true,
      builder: (sheetContext) => _PeoplePickerSheet(
        title: input.label,
        known: widget.knownPeople,
        rosterStream: widget.rosterStream,
        onPick: (name) => _appendName(controller, name),
      ),
    );
  }

  void _appendName(TextEditingController controller, String name) {
    final existing = controller.text.trimRight();
    controller.text = existing.isEmpty ? name : '$existing\n$name';
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  List<Widget> _nameFields(BuildContext context, ScheduleConfig config) {
    final widgets = <Widget>[];
    String? currentGroup;
    for (final input in config.inputs) {
      if (input.group != null && input.group != currentGroup) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 8, bottom: 10),
            child: Text(
              input.group!,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
      }
      currentGroup = input.group ?? currentGroup;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextField(
                controller: _controllerFor(input.key),
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: input.label,
                  hintText: 'One name per line',
                  alignLabelWithHint: true,
                ),
              ),

              TextButton.icon(
                onPressed: () => _openPeoplePicker(input),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: Text('Add people to ${input.label.toLowerCase()}'),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }
}

class _ScheduleOutput extends StatefulWidget {
  const _ScheduleOutput({required this.schedule});

  final DriverSchedule schedule;

  @override
  State<_ScheduleOutput> createState() => _ScheduleOutputState();
}

class _ScheduleOutputState extends State<_ScheduleOutput> {
  String? _selectedName;
  int _viewIndex = 0;

  @override
  void didUpdateWidget(_ScheduleOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.schedule, oldWidget.schedule)) {
      _selectedName = null;
      _viewIndex = 0;
    }
  }

  void _toggleName(String name) {
    setState(() => _selectedName = _selectedName == name ? null : name);
  }

  Future<void> _copy(ScheduleGroup group) async {
    await Clipboard.setData(
      ClipboardData(text: scheduleAsTabSeparatedText(widget.schedule, group)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          group.label == null
              ? 'Schedule copied'
              : '${group.label} schedule copied',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule;
    if (schedule.isEmpty) {
      return const _NoNamesYet();
    }

    final highlights = ScheduleHighlights.of(schedule);
    final views = schedule.config.effectiveAttendanceViews;
    final viewIndex = _viewIndex < views.length ? _viewIndex : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in schedule.config.effectiveRenderGroups) ...[
          _ScheduleChart(
            schedule: schedule,
            highlights: highlights,
            group: group,
            selectedName: _selectedName,
            onCopy: () => _copy(group),
          ),
          const SizedBox(height: 20),
        ],
        if (!highlights.isQuiet) ...[
          _Legend(highlights: highlights),
          const SizedBox(height: 24),
        ],
        _AttendanceSection(
          schedule: schedule,
          views: views,
          viewIndex: viewIndex,
          selectedName: _selectedName,
          onSelectView: (index) => setState(() => _viewIndex = index),
          onSelectName: _toggleName,
        ),
      ],
    );
  }
}

class _NoNamesYet extends StatelessWidget {
  const _NoNamesYet();

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Add at least one person to a role above, then generate.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

class _ScheduleChart extends StatelessWidget {
  const _ScheduleChart({
    required this.schedule,
    required this.highlights,
    required this.group,
    required this.selectedName,
    required this.onCopy,
  });

  final DriverSchedule schedule;
  final ScheduleHighlights highlights;
  final ScheduleGroup group;
  final String? selectedName;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final labels = schedule.config.roleLabels;
    final muted = PitPalette.inkMutedOf(context);
    final outline = PitPalette.outlineOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.label ?? 'Schedule',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.content_copy_outlined, size: 18),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Framed(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,

              columnWidths: const {0: FixedColumnWidth(48)},
              defaultColumnWidth: const MaxColumnWidth(
                IntrinsicColumnWidth(),
                FixedColumnWidth(116),
              ),
              border: TableBorder(
                horizontalInside: BorderSide(color: outline),
                verticalInside: BorderSide(color: outline),
              ),
              children: [
                TableRow(
                  children: [
                    const _HeaderCell(label: '#'),
                    for (final roleKey in group.roleKeys)
                      _HeaderCell(label: labels[roleKey] ?? roleKey),
                  ],
                ),
                for (var slot = 0; slot < schedule.slots; slot++)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Text(
                          '${slot + 1}',
                          style: pitCodeStyle(context, color: muted),
                        ),
                      ),
                      for (final roleKey in group.roleKeys)
                        _NameCell(
                          name: schedule.nameAt(roleKey, slot),
                          flag: _flagFor(slot, roleKey),
                          selected:
                              selectedName != null &&
                              schedule.nameAt(roleKey, slot) == selectedName,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  _CellFlag? _flagFor(int slot, String roleKey) {
    if (highlights.isConflict(slot, roleKey)) return _CellFlag.conflict;
    if (highlights.isBackToBack(slot, roleKey)) return _CellFlag.backToBack;
    if (highlights.isHandoff(slot, roleKey)) return _CellFlag.handoff;
    return null;
  }
}

enum _CellFlag {
  conflict('Same-slot conflict', Icons.warning_amber_rounded),
  backToBack('Back-to-back', Icons.fast_forward_rounded),
  handoff('Operates, then drives next match', Icons.swap_horiz_rounded);

  const _CellFlag(this.label, this.icon);

  final String label;
  final IconData icon;

  Color colorOf(BuildContext context) => switch (this) {
    _CellFlag.conflict => PitPalette.statusOverdueOf(context),
    _CellFlag.backToBack => PitPalette.statusPackingOf(context),
    _CellFlag.handoff => PitPalette.statusReadyOf(context),
  };
}

class _PeoplePickerSheet extends StatelessWidget {
  const _PeoplePickerSheet({
    required this.title,
    required this.known,
    required this.rosterStream,
    required this.onPick,
  });

  final String title;
  final Map<String, String> known;
  final Stream<List<UserProfile>>? rosterStream;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final stream = rosterStream;
    if (stream == null) {
      return _body(
        context,
        const [],
        rosterFailed: false,
        rosterLoading: false,
      );
    }
    return StreamBuilder<List<UserProfile>>(
      stream: stream,
      builder: (context, snapshot) => _body(
        context,
        snapshot.data ?? const <UserProfile>[],
        rosterFailed: snapshot.hasError,

        rosterLoading:
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasError,
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<UserProfile> roster, {
    required bool rosterFailed,
    required bool rosterLoading,
  }) {
    final muted = PitPalette.inkMutedOf(context);

    final byName = <String>{
      for (final profile in roster)
        if (profile.roles.isMember && profile.displayName.trim().isNotEmpty)
          profile.displayName.trim(),
      ...known.values,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add to $title',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              byName.isNotEmpty
                  ? 'Tap a name to add it. Tap it twice for two turns.'
                  : rosterLoading
                  ? 'Looking for people.'
                  : 'Nobody to offer yet. Type the names instead.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: muted),
            ),
            if (rosterFailed) ...[
              const SizedBox(height: 4),
              Text(
                'Only people already on the schedule are listed.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in byName)
                      ActionChip(
                        label: Text(name),

                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        onPressed: () => onPick(name),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.name,
    required this.flag,
    required this.selected,
  });

  final String name;
  final _CellFlag? flag;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = PitPalette.accentOf(context);

    final cellFlag = flag;
    final label = name.isEmpty ? 'Nobody' : name;

    final flagColor = cellFlag?.colorOf(context);

    return Semantics(
      label: cellFlag == null ? label : '$label, ${cellFlag.label}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: flagColor?.withValues(alpha: 0.20),
          border: selected
              ? Border.all(color: accent, width: 2)
              : flagColor == null
              ? null
              : Border.all(color: flagColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cellFlag != null) ...[
              Icon(cellFlag.icon, size: 14, color: flagColor),
              const SizedBox(width: 6),
            ],
            Text(
              name.isEmpty ? '-' : name,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.highlights});

  final ScheduleHighlights highlights;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final warnings = <String>[
      if (highlights.conflicts.isNotEmpty)
        'Someone is booked into two roles in the same match. Add more names '
            'to that role to resolve it.',
      if (highlights.backToBack.isNotEmpty)
        'Some back-to-back matches were unavoidable with the names given.',
      if (highlights.handoffMissed > 0)
        '${highlights.handoffMissed} '
            '${highlights.handoffMissed == 1 ? 'match' : 'matches'} could not '
            'hand off: the next driver had no operator turn to spare. Add '
            'them to the operator list for a closer match.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            if (highlights.conflicts.isNotEmpty)
              const _LegendItem(flag: _CellFlag.conflict),
            if (highlights.backToBack.isNotEmpty)
              const _LegendItem(flag: _CellFlag.backToBack),
            if (highlights.handoffs.isNotEmpty)
              const _LegendItem(flag: _CellFlag.handoff),
          ],
        ),
        for (final warning in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    warning,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.flag});

  final _CellFlag flag;

  @override
  Widget build(BuildContext context) {
    final color = flag.colorOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.20),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(PitPalette.radiusSm),
          ),
          child: Icon(flag.icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(flag.label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _AttendanceSection extends StatelessWidget {
  const _AttendanceSection({
    required this.schedule,
    required this.views,
    required this.viewIndex,
    required this.selectedName,
    required this.onSelectView,
    required this.onSelectName,
  });

  final DriverSchedule schedule;
  final List<AttendanceView> views;
  final int viewIndex;
  final String? selectedName;
  final ValueChanged<int> onSelectView;
  final ValueChanged<String> onSelectName;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final outline = PitPalette.outlineOf(context);
    final accent = PitPalette.accentOf(context);
    final table = AttendanceTable.of(schedule, views[viewIndex]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Matches per person',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          'Tap a name to highlight their matches above.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        if (views.length > 1) ...[
          SegmentedButton<int>(
            segments: [
              for (var index = 0; index < views.length; index++)
                ButtonSegment<int>(
                  value: index,
                  label: Text(views[index].label),
                ),
            ],
            selected: {viewIndex},
            onSelectionChanged: (selection) => onSelectView(selection.first),
          ),
          const SizedBox(height: 12),
        ],
        _Framed(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              defaultColumnWidth: const MaxColumnWidth(
                IntrinsicColumnWidth(),
                FixedColumnWidth(104),
              ),
              border: TableBorder(horizontalInside: BorderSide(color: outline)),
              children: [
                TableRow(
                  children: [
                    const _HeaderCell(label: 'Person'),
                    for (final column in table.columns)
                      _HeaderCell(label: column.label),
                    const _HeaderCell(label: 'Matches'),
                  ],
                ),
                for (final entry in table.rows)
                  TableRow(
                    decoration: entry.name == selectedName
                        ? BoxDecoration(color: accent.withValues(alpha: 0.16))
                        : null,
                    children: [
                      _AttendanceCell(
                        onTap: () => onSelectName(entry.name),
                        child: Text(
                          entry.name,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final count in entry.counts)
                        _AttendanceCell(
                          onTap: () => onSelectName(entry.name),
                          child: count == null
                              ? Text(
                                  'not listed',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: muted),
                                )
                              : Text(
                                  '$count',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                        ),
                      _AttendanceCell(
                        onTap: () => onSelectName(entry.name),
                        child: Text(
                          '${entry.total}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AttendanceCell extends StatelessWidget {
  const _AttendanceCell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: child,
      ),
    );
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PitPalette.surfaceOf(context),
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        border: Border.all(color: PitPalette.outlineOf(context)),
      ),
      child: child,
    );
  }
}

class _ImportAction extends StatelessWidget {
  const _ImportAction({
    required this.busy,
    required this.competition,
    required this.onImport,
  });

  final bool busy;
  final String competition;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onImport,
          icon: busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.event_available),
          label: Text(busy ? 'Importing' : 'Add to the $competition schedule'),
        ),
        const SizedBox(height: 6),
        Text(
          'One match block per match, so a person double-booked against a pit '
          'duty shows up as a conflict like any other clash.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: PitPalette.inkMutedOf(context)),
        ),
      ],
    );
  }
}
