import 'package:tba_client/tba_client.dart';

import '../models/driver_schedule.dart';

typedef EventMatchLoader = Future<EventMatchSchedule> Function(
  String eventKey,
  List<int> teams,
);

Future<EventMatchSchedule> loadEventMatchSchedule(
  TbaClient client,
  String eventKey,
  List<int> teams,
) async {
  final List<TbaScheduleMatch> matches;
  try {
    matches = await client.getEventMatches(eventKey);
  } catch (error) {
    throw EventScheduleException(tbaErrorMessage(error));
  }
  return eventMatchScheduleFrom(eventKey, teams, matches);
}

String tbaErrorMessage(Object error) => switch (error) {
  TbaApiKeyMissingException() =>
    'The team TBA key is not set. An admin adds it as appConfig/apiKeys.tba '
        'in Firestore.',
  TbaApiException(:final statusCode) =>
    'The Blue Alliance returned an error ($statusCode).',
  _ => 'Could not reach The Blue Alliance. Check the connection and try again.',
};

EventMatchSchedule eventMatchScheduleFrom(
  String eventKey,
  List<int> teams,
  List<TbaScheduleMatch> matches,
) {
  bool plays(TbaScheduleMatch match, int team) =>
      match.redTeams.contains(team) || match.blueTeams.contains(team);

  final rows = [
    for (final match in matches)
      if (match.compLevel == 'qm' && teams.any((t) => plays(match, t))) match,
  ]..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
  if (rows.isEmpty) {
    throw EventScheduleException(
      'No qualification matches at $eventKey for these teams. Check the event '
      'key and team numbers, or the schedule may not be posted yet.',
    );
  }
  final byRobot = [
    for (final team in teams)
      [
        for (var slot = 0; slot < rows.length; slot++)
          if (plays(rows[slot], team)) slot,
      ],
  ];
  final missing = [
    for (var i = 0; i < teams.length; i++)
      if (byRobot[i].isEmpty) teams[i],
  ];
  if (missing.isNotEmpty) {
    throw EventScheduleException(
      'No qualification matches for team ${missing.join(', ')} at $eventKey.',
    );
  }
  return EventMatchSchedule(
    eventKey: eventKey,
    teams: teams,
    matchNumbers: [for (final match in rows) match.matchNumber],
    plays: byRobot,
  );
}

class EventScheduleException implements Exception {
  const EventScheduleException(this.message);

  final String message;

  @override
  String toString() => message;
}
