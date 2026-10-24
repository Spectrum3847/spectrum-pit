import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/wpilog_reader.dart';

import 'support/robot_log_fixtures.dart';

void main() {
  test('reads match identity and timing from a WPILib log', () {
    final f = readWpiLogFacts(matchLog());
    expect(f.layout, 'wpilib');
    expect(f.team, 3847);

    expect(f.event, 'TXMAN1');
    expect(f.matchType, 'Qualification');
    expect(f.matchNumber, 3);
    expect(f.firstTs, 0);
    expect(f.lastTs, 200);
    expect(f.matchStart, 10);
    expect(f.enabledSeconds, 150);
    expect(f.unixStartMs, 1760629990000);
    expect(f.unixEndMs, 1760630190000);
    expect(f.toUnixMs(f.matchStart), 1760630000000);
    expect(f.phases, hasLength(1));
    expect(f.phases.single.phase, 'teleop');
    expect(f.phases.single.start, 10);
    expect(f.phases.single.end, 160);
  });

  test('tags WPILib phases by DS:autonomous at the moment of enable', () {
    final b = WpiLogBuilder()
      ..start('DS:enabled', 'boolean')
      ..start('DS:autonomous', 'boolean');
    b
      ..value('DS:autonomous', 1, true)
      ..value('DS:enabled', 2, true)
      ..value('DS:enabled', 17, false)
      ..value('DS:autonomous', 18, false)
      ..value('DS:enabled', 20, true)
      ..value('DS:enabled', 40, false);
    final f = readWpiLogFacts(b.build());
    expect(f.phases.map((p) => p.phase), ['auto', 'teleop']);
    expect(f.phases.map((p) => p.start), [2, 20]);
    expect(f.phases.map((p) => p.end), [17, 40]);
    expect(f.matchStart, 2);
    expect(f.enabledSeconds, 35);
  });

  test('tags AdvantageKit phases by RobotMode', () {
    final b = WpiLogBuilder()
      ..start('/DriverStation/Enabled', 'boolean')
      ..start('/DriverStation/RobotMode', 'string');
    b
      ..value('/DriverStation/RobotMode', 3, 'AUTONOMOUS')
      ..value('/DriverStation/Enabled', 4, true)
      ..value('/DriverStation/Enabled', 20, false)
      ..value('/DriverStation/RobotMode', 28, 'TELEOPERATED')
      ..value('/DriverStation/Enabled', 30, true)
      ..value('/DriverStation/RobotMode', 50, 'TELEOPERATED');
    final f = readWpiLogFacts(b.build());
    expect(f.layout, 'advantagekit');
    expect(f.phases.map((p) => p.phase), ['auto', 'teleop']);
    expect(f.phases.map((p) => p.start), [4, 30]);

    expect(f.phases.map((p) => p.end), [20, 50]);
  });

  test('a log that was never enabled has no phases', () {
    final b = WpiLogBuilder()..start('DS:enabled', 'boolean');
    b.value('DS:enabled', 5, false);
    final f = readWpiLogFacts(b.build());
    expect(f.phases, isEmpty);
    expect(f.matchStart, isNull);
  });

  test('reads an AdvantageKit log', () {
    final b = WpiLogBuilder()
      ..start('/DriverStation/Enabled', 'boolean')
      ..start('/DriverStation/MatchType', 'int64')
      ..start('/DriverStation/MatchNumber', 'int64')
      ..start('/DriverStation/EventName', 'string')
      ..start('/DriverStation/AllianceStation', 'int64')
      ..start('/SystemStats/EpochTimeMicros', 'int64');
    b
      ..value('/DriverStation/AllianceStation', 1, 0)
      ..value('/DriverStation/EventName', 2, 'txman1')
      ..value('/DriverStation/MatchType', 2, 2)
      ..value('/DriverStation/MatchNumber', 2, 12)
      ..value('/DriverStation/AllianceStation', 3, 5)
      ..value('/SystemStats/EpochTimeMicros', 3, 1760630000000000)
      ..value('/DriverStation/Enabled', 4, true);
    final f = readWpiLogFacts(b.build());
    expect(f.layout, 'advantagekit');
    expect(f.matchType, 'Qualification');
    expect(f.matchNumber, 12);
    expect(f.alliance, 'Blue');
    expect(f.station, 2);
    expect(f.enabledSeconds, 0);
    expect(f.unixOffset, 1760630000 - 3);
  });

  test('a truncated log is read up to where it stops', () {
    final bytes = matchLog();
    final f = readWpiLogFacts(
      Uint8List.sublistView(bytes, 0, bytes.length - 5),
    );
    expect(f.event, 'TXMAN1');
    expect(f.lastTs, 160);
  });

  test('rejects a file that is not a wpilog', () {
    expect(
      () => readWpiLogFacts(Uint8List.fromList(List.filled(40, 1))),
      throwsA(isA<WpiLogFormatException>()),
    );
  });

  test('round-trips through JSON', () {
    final f = readWpiLogFacts(matchLog());
    expect(WpiLogFacts.fromJson(f.toJson()).toJson(), f.toJson());
  });

  test('facts saved before phases existed read back with none', () {
    final json = readWpiLogFacts(matchLog()).toJson()..remove('phases');
    expect(WpiLogFacts.fromJson(json).phases, isEmpty);
  });
}
