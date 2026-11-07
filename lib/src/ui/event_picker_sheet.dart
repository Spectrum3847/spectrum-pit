import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../models/active_event.dart';
import '../services/event_match_schedule.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';
import '../widgets/glass_modal.dart';

typedef EventsLoader = Future<List<TbaEvent>> Function(int year);

Future<TbaEvent?> showEventPicker(
  BuildContext context, {
  required EventsLoader loadEvents,
  String? currentKey,
  DateTime Function()? clock,
}) {
  return showGlassModalBottomSheet<TbaEvent>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => EventPickerSheet(
      loadEvents: loadEvents,
      currentKey: currentKey,
      clock: clock ?? DateTime.now,
    ),
  );
}

class EventPickerSheet extends StatefulWidget {
  const EventPickerSheet({
    required this.loadEvents,
    required this.clock,
    this.currentKey,
    super.key,
  });

  final EventsLoader loadEvents;
  final DateTime Function() clock;
  final String? currentKey;

  @override
  State<EventPickerSheet> createState() => _EventPickerSheetState();
}

class _EventPickerSheetState extends State<EventPickerSheet> {
  late final DateTime _today = widget.clock();
  late int _year = _today.year;
  final Map<int, Future<List<TbaEvent>>> _byYear = {};
  final TextEditingController _search = TextEditingController();
  bool _showAll = false;

  Future<List<TbaEvent>> _events(int year) => _byYear[year] ??= widget
      .loadEvents(year)
      .then((events) => [...events]..sort(_byStart));

  static int _byStart(TbaEvent a, TbaEvent b) {
    final byDate = (a.startDate ?? '9999').compareTo(b.startDate ?? '9999');
    return byDate != 0 ? byDate : a.name.compareTo(b.name);
  }

  void _retry() =>
      setState(() => _byYear.remove(_showAll ? _year : _today.year));

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final year = _showAll ? _year : _today.year;
    final header = <Widget>[
      Text('Team event', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        'Every device follows the event you pick.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        autocorrect: false,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Search by name or key',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show all events'),
        value: _showAll,
        onChanged: (value) => setState(() => _showAll = value),
      ),
      if (_showAll)
        Row(
          children: [
            IconButton(
              tooltip: 'Previous season',
              onPressed: () => setState(() => _year--),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '$_year',
                textAlign: TextAlign.center,
                style: pitCodeStyle(context),
              ),
            ),
            IconButton(
              tooltip: 'Next season',
              onPressed: _year < _today.year
                  ? () => setState(() => _year++)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: FutureBuilder<List<TbaEvent>>(
            future: _events(year),
            builder: (context, snapshot) {
              final List<TbaEvent> rows;
              final Widget? state;
              if (snapshot.hasError) {
                rows = const [];
                state = _Message(
                  text: tbaErrorMessage(snapshot.error!),
                  action: TextButton(
                    onPressed: _retry,
                    child: const Text('Try again'),
                  ),
                );
              } else if (!snapshot.hasData) {
                rows = const [];
                state = const Center(child: CircularProgressIndicator());
              } else {
                rows = _filter(snapshot.data!);
                state = rows.isNotEmpty
                    ? null
                    : _Message(
                        text: _search.text.trim().isNotEmpty
                            ? 'No events match that search.'
                            : _showAll
                            ? 'No events this season.'
                            : 'No nearby events. Turn on Show all events '
                                  'to pick another.',
                      );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                itemCount: header.length + (state == null ? rows.length : 1),
                itemBuilder: (context, i) {
                  if (i < header.length) return header[i];
                  if (state != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: state,
                    );
                  }
                  final event = rows[i - header.length];
                  return _EventRow(
                    event: event,
                    selected: event.key == widget.currentKey,
                    onTap: () => Navigator.of(context).pop(event),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  List<TbaEvent> _filter(List<TbaEvent> events) {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final event in events)
        if ((_showAll ||
                query.isNotEmpty ||
                isEventNearby(event.startDate, event.endDate, _today)) &&
            (query.isEmpty ||
                event.name.toLowerCase().contains(query) ||
                event.key.contains(query)))
          event,
    ];
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final TbaEvent event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final dates = formatEventDates(event.startDate, event.endDate);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 10,
      selected: selected,
      title: Text(event.name),
      subtitle: Text(
        dates.isEmpty ? event.key : '${event.key}  $dates',
        style: pitCodeStyle(context, color: muted),
      ),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
      onTap: onTap,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: PitPalette.inkMutedOf(context)),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

const _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

String formatEventDates(String? startDate, String? endDate) {
  final start = DateTime.tryParse(startDate ?? '');
  if (start == null) return '';
  final end = DateTime.tryParse(endDate ?? '') ?? start;
  final from = '${_months[start.month - 1]} ${start.day}';
  if (end.year == start.year && end.month == start.month) {
    return end.day == start.day ? from : '$from-${end.day}';
  }
  return '$from-${_months[end.month - 1]} ${end.day}';
}
