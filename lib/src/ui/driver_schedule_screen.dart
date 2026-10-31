import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/driver_schedule.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../services/driver_schedule_generator.dart';
import '../services/driver_schedule_import.dart';
import '../services/driver_schedule_store.dart';
import '../services/event_match_schedule.dart';
import '../services/schedule_image.dart';
import '../services/schedule_image_share.dart';
import '../state/pit_shift_controller.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';
import '../widgets/glass_modal.dart';

class DriverScheduleScreen extends StatefulWidget {
  const DriverScheduleScreen({
    super.key,
    this.generator,
    this.knownPeople = const <String, String>{},
    this.rosterStream,
    this.shiftController,
    this.competition,
    this.competitions = const <String>[],
    this.store,
    this.eventMatchLoader,
    this.eventKey,
  });

  final DriverScheduleGenerator? generator;

  final Map<String, String> knownPeople;

  final Stream<List<UserProfile>>? rosterStream;

  final PitShiftController? shiftController;

  final String? competition;

  final List<String> competitions;

  final DriverScheduleStore? store;

  final EventMatchLoader? eventMatchLoader;

  final String? eventKey;

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
    _competitionController = TextEditingController(
      text: widget.competition ?? '',
    );
    _eventController.text = widget.eventKey ?? '';
    unawaited(_restore());
  }

  late final TextEditingController _competitionController;

  String get _competition => _competitionController.text.trim();

  final Map<String, TextEditingController> _nameControllers = {};
  final TextEditingController _slotsController = TextEditingController(
    text: '6',
  );

  final TextEditingController _eventController = TextEditingController();
  final Map<int, TextEditingController> _teamControllers = {};

  int _modeIndex = 0;
  bool _handoff = false;
  bool _loading = false;
  String? _slotsError;
  String? _eventError;
  DriverSchedule? _schedule;

  Map<String, List<String>> _scheduleInputs = const {};

  ScheduleConfig get _config => scheduleConfigs[_modeIndex];

  bool get _offersEvent =>
      widget.eventMatchLoader != null && _config.renderGroups != null;

  String get _eventKey =>
      _offersEvent ? _eventController.text.trim().toLowerCase() : '';

  @override
  void dispose() {
    for (final controller in [
      ..._nameControllers.values,
      ..._teamControllers.values,
    ]) {
      controller.dispose();
    }
    _slotsController.dispose();
    _competitionController.dispose();
    _eventController.dispose();
    super.dispose();
  }

  TextEditingController _teamController(int robot) =>
      _teamControllers.putIfAbsent(robot, TextEditingController.new);

  TextEditingController _controllerFor(String inputKey) =>
      _nameControllers.putIfAbsent(inputKey, TextEditingController.new);

  void _selectMode(int index) {
    if (index == _modeIndex) return;
    setState(() {
      _modeIndex = index;

      _schedule = null;
      _eventError = null;
    });
  }

  void _setHandoff(bool value) {
    setState(() => _handoff = value);

    if (_schedule != null) _generate(reuse: _schedule!.matches);
  }

  Future<void> _generate({EventMatchSchedule? reuse}) async {
    if (_loading) return;
    final config = _config;
    final eventKey = _eventKey;
    int? slots;
    EventMatchSchedule? matches;

    void fail({String? slotsError, String? eventError}) => setState(() {
      _loading = false;
      _slotsError = slotsError;
      _eventError = eventError;
      _schedule = null;
    });

    if (eventKey.isEmpty) {
      final error = validateSlotCount(_slotsController.text);
      if (error != null) return fail(slotsError: error);
      slots = int.parse(_slotsController.text.trim());
    } else {
      final teams = _typedTeams(config);
      if (teams.any((team) => team == null || team < 1)) {
        return fail(eventError: 'Enter a team number for every robot.');
      }
      final wanted = teams.whereType<int>().toList();
      if (reuse != null &&
          reuse.eventKey == eventKey &&
          listEquals(reuse.teams, wanted)) {
        matches = reuse;
      } else {
        setState(() {
          _loading = true;
          _slotsError = null;
          _eventError = null;
        });
        try {
          matches = await widget.eventMatchLoader!(eventKey, wanted);
        } catch (error) {
          if (!mounted) return;
          return fail(
            eventError: error is EventScheduleException
                ? error.message
                : 'Could not load the matches: $error',
          );
        }
        if (!mounted) return;

        if (!identical(config, _config)) {
          return setState(() => _loading = false);
        }
        if (_eventKey != eventKey || !listEquals(_typedTeams(config), teams)) {
          setState(() => _loading = false);
          return _generate();
        }
      }
    }

    final inputs = {
      for (final input in config.inputs)
        input.key: parseNameList(_controllerFor(input.key).text),
    };
    final DriverSchedule schedule;
    try {
      schedule = _generator.generate(
        config,
        inputs,
        slots: slots,
        matches: matches,
        handoff: _handoff,
      );
    } catch (error) {
      final message =
          'Could not build the rotation: '
          '${error is ArgumentError ? error.message : error}';
      return matches == null
          ? fail(slotsError: message)
          : fail(eventError: message);
    }
    setState(() {
      _loading = false;
      _slotsError = null;
      _eventError = null;
      _schedule = schedule;
      _scheduleInputs = inputs;
    });
    _remember(schedule, inputs);
  }

  List<int?> _typedTeams(ScheduleConfig config) => [
    for (var robot = 0; robot < config.effectiveRenderGroups.length; robot++)
      int.tryParse(_teamController(robot).text.trim()),
  ];

  void _pickCompetition(String name) {
    setState(() => _competitionController.text = name);
  }

  void _remember(DriverSchedule schedule, Map<String, List<String>> inputs) {
    final competition = _competition;
    if (competition.isEmpty) {
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
              matches: schedule.matches,
            ),
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _restore() async {
    final competition = _competition;
    if (competition.isEmpty) {
      return;
    }
    final SavedDriverSchedule? loaded;
    try {
      loaded = await _store.load(competition);
    } catch (error) {
      debugPrint('Could not restore the saved rotation: $error');
      return;
    }
    if (loaded == null || !mounted || competition != _competition) {
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
      final matches = saved.matches;
      if (matches != null) {
        _eventController.text = matches.eventKey;
        for (var robot = 0; robot < matches.teams.length; robot++) {
          _teamController(robot).text = '${matches.teams[robot]}';
        }
      }

      _schedule = saved.toSchedule();
      _scheduleInputs = saved.inputs;
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
            showSelectedIcon: false,
            segments: [
              for (var index = 0; index < scheduleConfigs.length; index++)
                ButtonSegment<int>(
                  value: index,
                  label: _SegmentLabel(scheduleConfigs[index].label),
                ),
            ],
            selected: {_modeIndex},
            onSelectionChanged: (selection) => _selectMode(selection.first),
          ),
          const SizedBox(height: 20),
          ..._nameFields(context, config),
          if (_offersEvent) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _eventController,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _generate(),
              decoration: InputDecoration(
                labelText: 'Event key (optional)',
                hintText: '2026txhou',
                helperText:
                    'Schedules the real qualification matches from The Blue '
                    'Alliance. Each robot needs a team number.',
                helperMaxLines: 3,
                errorText: _eventError,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: TextField(
                  controller: _slotsController,

                  enabled: _eventKey.isEmpty,
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
                    onPressed: _loading ? null : _generate,
                    icon: _loading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.casino_outlined),
                    label: Text(_loading ? 'Loading matches' : 'Generate'),
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
              competitionController: _competitionController,
              competitions: widget.competitions,
              onCompetitionChanged: () => setState(() {}),
              onPickCompetition: _pickCompetition,
              onImport: () => _import(schedule),
            ),
          ],
        ],
      ),
    );
  }

  bool _importing = false;

  bool get _canImport => widget.shiftController != null;

  Future<void> _import(DriverSchedule schedule) async {
    final controller = widget.shiftController;
    final competition = _competition;
    if (controller == null || competition.isEmpty) {
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

    _remember(schedule, _scheduleInputs);

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

  Future<bool?> _askReplaceOrAdd(int existing) => showGlassConfirmDialog<bool>(
    context: context,
    title: 'Already imported',
    content: Text(
      '$existing shift${existing == 1 ? '' : 's'} on this schedule came '
      'from a previous import. Replace them, or add these alongside?',
    ),
    actionsBuilder: (dialogContext) => [
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
  );

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPeoplePicker(ScheduleInput input) {
    final controller = _controllerFor(input.key);
    return showGlassModalBottomSheet<void>(
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
      final robot = _offersEvent && input.group != currentGroup
          ? config.effectiveRenderGroups.indexWhere(
              (group) => group.label == input.group,
            )
          : -1;
      currentGroup = input.group ?? currentGroup;
      if (robot >= 0) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 180,
                child: TextField(
                  controller: _teamController(robot),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Team number',
                    hintText: 'With an event key',
                  ),
                ),
              ),
            ),
          ),
        );
      }
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

  Future<void> _shareImage(ScheduleGroup group, Rect origin) async {
    try {
      final image = await scheduleImage(widget.schedule, group);
      await shareScheduleImage(image, origin: origin);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share the image: $error')),
      );
    }
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

    final matches = schedule.matches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matches != null) ...[
          Text(
            _matchesSummary(matches),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: PitPalette.inkMutedOf(context)),
          ),
          const SizedBox(height: 16),
        ],
        for (final group in schedule.config.effectiveRenderGroups)
          if (schedule.shownRoleKeys(group).isNotEmpty) ...[
            _ScheduleChart(
              schedule: schedule,
              highlights: highlights,
              group: group,
              selectedName: _selectedName,
              onCopy: () => _copy(group),
              onShareImage: (origin) => _shareImage(group, origin),
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

String _matchesSummary(EventMatchSchedule matches) {
  final count = matches.matchNumbers.length;
  final loaded =
      '$count match${count == 1 ? '' : 'es'} loaded from '
      '${matches.eventKey}.';
  final shared = matches.sharedMatches;
  if (shared.isEmpty) return '$loaded No two robots share a match.';
  final list = [
    for (final entry in shared)
      'Q${entry.match} (robots ${entry.robots.join(' and ')})',
  ].join(', ');
  return '$loaded Robots in the same match: $list.';
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
    required this.onShareImage,
  });

  final DriverSchedule schedule;
  final ScheduleHighlights highlights;
  final ScheduleGroup group;
  final String? selectedName;
  final VoidCallback onCopy;

  final ValueChanged<Rect> onShareImage;

  @override
  Widget build(BuildContext context) {
    final labels = schedule.config.roleLabels;
    final shown = schedule.shownRoleKeys(group);
    final team = schedule.teamFor(group);
    final muted = PitPalette.inkMutedOf(context);
    final outline = PitPalette.outlineOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              [
                group.label ?? 'Schedule',
                if (team != null) 'team $team',
              ].join(', '),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Wrap(
              children: [
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                  label: const Text('Copy'),
                ),
                Builder(
                  builder: (buttonContext) => TextButton.icon(
                    onPressed: () => onShareImage(_rectOf(buttonContext)),
                    icon: Icon(
                      scheduleImageSaves
                          ? Icons.save_alt
                          : Icons.ios_share_outlined,
                      size: 18,
                    ),
                    label: Text(
                      scheduleImageSaves ? 'Save image' : 'Share image',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Framed(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,

              columnWidths: const {
                0: MaxColumnWidth(IntrinsicColumnWidth(), FixedColumnWidth(48)),
              },
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
                    for (final roleKey in shown)
                      _HeaderCell(label: labels[roleKey] ?? roleKey),
                  ],
                ),
                for (final slot in schedule.slotsFor(group))
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Text(
                          schedule.slotLabel(slot),
                          style: pitCodeStyle(context, color: muted),
                        ),
                      ),
                      for (final roleKey in shown)
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

  static Rect _rectOf(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
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

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, softWrap: false),
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
            showSelectedIcon: false,
            segments: [
              for (var index = 0; index < views.length; index++)
                ButtonSegment<int>(
                  value: index,
                  label: _SegmentLabel(views[index].label),
                ),
            ],
            selected: {viewIndex},
            onSelectionChanged: (selection) => onSelectView(selection.first),
          ),
          const SizedBox(height: 12),
        ],
        if (table.columns.isEmpty)
          Text(
            "No names on this robot's lists.",
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: muted),
          )
        else
          _Framed(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                defaultColumnWidth: const MaxColumnWidth(
                  IntrinsicColumnWidth(),
                  FixedColumnWidth(104),
                ),
                border: TableBorder(
                  horizontalInside: BorderSide(color: outline),
                ),
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
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
    required this.competitionController,
    required this.competitions,
    required this.onCompetitionChanged,
    required this.onPickCompetition,
    required this.onImport,
  });

  final bool busy;
  final TextEditingController competitionController;
  final List<String> competitions;
  final VoidCallback onCompetitionChanged;
  final ValueChanged<String> onPickCompetition;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final name = competitionController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (competitions.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            children: [
              for (final option in competitions)
                ChoiceChip(
                  label: Text(option),
                  selected: name == option,
                  onSelected: (_) => onPickCompetition(option),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: competitionController,
          textInputAction: TextInputAction.done,
          onChanged: (_) => onCompetitionChanged(),
          decoration: const InputDecoration(labelText: 'Competition'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy || name.isEmpty ? null : onImport,
          icon: busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.event_available),
          label: Text(
            busy
                ? 'Importing'
                : name.isEmpty
                ? 'Add to the schedule'
                : 'Add to the $name schedule',
          ),
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
