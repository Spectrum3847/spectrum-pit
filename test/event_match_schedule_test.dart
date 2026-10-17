import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/driver_schedule.dart';
import 'package:spectrumpit/src/services/event_match_schedule.dart';
import 'package:spectrumpit/src/services/team_tba_config.dart';
import 'package:tba_client/tba_client.dart';

TbaScheduleMatch _qm(int number, List<int> red, List<int> blue) =>
    TbaScheduleMatch(
      key: '2026txhou_qm$number',
      compLevel: 'qm',
      matchNumber: number,
      redTeams: red,
      blueTeams: blue,
    );

void main() {
  group('eventMatchScheduleFrom', () {
    final matches = [
      _qm(3, [3847, 1, 2], [3, 4, 5]),
      _qm(1, [6, 7, 8], [9, 10, 118]),
      _qm(2, [11, 12, 13], [14, 15, 16]),
      _qm(5, [3847, 21, 22], [118, 23, 24]),
      const TbaScheduleMatch(
        key: '2026txhou_sf1m1',
        compLevel: 'sf',
        matchNumber: 1,
        redTeams: [3847],
        blueTeams: [118],
      ),
    ];

    test('one slot per qualification match a robot plays, in order', () {
      final schedule = eventMatchScheduleFrom('2026txhou', [
        3847,
        118,
      ], matches);

      expect(schedule.matchNumbers, [1, 3, 5]);
      expect(schedule.plays, [
        [1, 2],
        [0, 2],
      ]);
      expect(schedule.teams, [3847, 118]);
    });

    test('lists the matches robots share', () {
      final schedule = eventMatchScheduleFrom('2026txhou', [
        3847,
        118,
      ], matches);

      final shared = schedule.sharedMatches.single;
      expect(shared.match, 5);
      expect(shared.robots, [1, 2]);
    });

    test('names a team with no qualification matches', () {
      expect(
        () => eventMatchScheduleFrom('2026txhou', [3847, 254], matches),
        throwsA(
          isA<EventScheduleException>().having(
            (e) => e.message,
            'message',
            contains('team 254'),
          ),
        ),
      );
    });

    test('an event with no matches for these teams says to check the key', () {
      expect(
        () => eventMatchScheduleFrom('2026xxxx', [3847], const []),
        throwsA(
          isA<EventScheduleException>().having(
            (e) => e.message,
            'message',
            contains('Check the event key'),
          ),
        ),
      );
    });
  });

  group('loadEventMatchSchedule', () {
    Future<String> failureOf(TbaClient client) async {
      try {
        await loadEventMatchSchedule(client, '2026txhou', [3847]);
      } on EventScheduleException catch (error) {
        return error.message;
      }
      fail('expected an EventScheduleException');
    }

    test('no key asks for the team key', () async {
      final client = TbaClient(config: InMemoryTbaConfig());

      expect(await failureOf(client), contains('appConfig/apiKeys.tba'));
    });

    test('an API error reports its status', () async {
      final client = TbaClient(
        config: InMemoryTbaConfig('key'),
        httpClient: MockClient((_) async => http.Response('nope', 401)),
      );

      expect(await failureOf(client), contains('(401)'));
    });

    test('no connection says so', () async {
      final client = TbaClient(
        config: InMemoryTbaConfig('key'),
        httpClient: MockClient((_) => throw http.ClientException('offline')),
      );

      expect(await failureOf(client), contains('Could not reach'));
    });

    test('sends the key and parses the schedule', () async {
      late http.Request seen;
      final client = TbaClient(
        config: InMemoryTbaConfig('key'),
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            '[{"key":"2026txhou_qm4","comp_level":"qm","match_number":4,'
            '"alliances":{"red":{"team_keys":["frc3847","frc1","frc2"]},'
            '"blue":{"team_keys":["frc3","frc4","frc5"]}}}]',
            200,
          );
        }),
      );

      final schedule = await loadEventMatchSchedule(client, '2026txhou', [
        3847,
      ]);

      expect(seen.headers['X-TBA-Auth-Key'], 'key');
      expect(seen.url.path, endsWith('/event/2026txhou/matches/simple'));
      expect(schedule.matchNumbers, [4]);
    });
  });

  group('EventMatchSchedule', () {
    test('round trips through JSON', () {
      const original = EventMatchSchedule(
        eventKey: '2026txhou',
        teams: [3847, 118],
        matchNumbers: [1, 3],
        plays: [
          [0],
          [0, 1],
        ],
      );

      final copy = EventMatchSchedule.fromJson(original.toJson());

      expect(copy.eventKey, original.eventKey);
      expect(copy.teams, original.teams);
      expect(copy.matchNumbers, original.matchNumbers);
      expect(copy.plays, original.plays);
    });
  });

  test('a malformed saved schedule reads leniently', () {
    final copy = EventMatchSchedule.fromJson({
      'eventKey': 7,
      'teams': 'nope',
      'matchNumbers': [4, 9],
      'plays': [
        [0, 1, 5, -1],
        'bad',
      ],
    });

    expect(copy.eventKey, '');
    expect(copy.teams, isEmpty);
    expect(copy.plays, [
      [0, 1],
      <int>[],
    ]);
  });

  group('TeamTbaConfig', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('uses the Firestore key and keeps it for offline use', () async {
      expect(
        await TeamTbaConfig(fetchRemote: () async => ' team ').resolveApiKey(),
        'team',
      );

      expect(
        await TeamTbaConfig(
          fetchRemote: () async => throw StateError('offline'),
        ).resolveApiKey(),
        'team',
      );
    });

    test('a cleared key is forgotten', () async {
      await TeamTbaConfig(fetchRemote: () async => 'team').resolveApiKey();

      final config = TeamTbaConfig(
        fetchRemote: () async => '',
        fallback: InMemoryTbaConfig('build'),
      );

      expect(await config.resolveApiKey(), 'build');
    });

    test('with no backend, falls back to the build key', () async {
      final config = TeamTbaConfig(fallback: InMemoryTbaConfig('build'));

      expect(await config.resolveApiKey(), 'build');
    });
  });
}
