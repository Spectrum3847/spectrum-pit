import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/robot_log_file.dart';
import 'package:spectrumpit/src/services/wpilog_reader.dart';

WpiLogFacts _facts({
  int? team = 3847,
  String? event = 'TXMAN1',
  String? matchType = 'Qualification',
  int? matchNumber = 15,
  int? replay,
  int? unixStartMs = 1760630000000,
  double lastTs = 300,
  List<WpiPhase> phases = const [],
}) => WpiLogFacts(
  layout: 'wpilib',
  team: team,
  event: event,
  matchType: matchType,
  matchNumber: matchNumber,
  replay: replay,
  alliance: null,
  station: null,
  fmsAttached: event != null,
  firstTs: 0,
  lastTs: lastTs,
  unixOffset: unixStartMs == null ? null : unixStartMs / 1000,
  matchStart: 20,
  enabledSeconds: 150,
  phases: phases,
);

RobotLogFile _log(String rel, WpiLogFacts facts, {int? sourceTeam}) =>
    RobotLogFile(
      rel: rel,
      kind: RobotLogKind.wpilog,
      size: 1,
      wpilog: facts,
      sourceTeam: sourceTeam,
    );

RobotLogFile _rewind(
  String rel,
  int startMs, {
  String camera = 'limelight-left',
  int? team = 3847,
  double? fpgaStart,
  double? fpgaEnd,
  int? modifiedMs,
}) => RobotLogFile(
  rel: rel,
  kind: RobotLogKind.rwnd,
  size: 1,
  sourceTeam: team,
  modifiedMs: modifiedMs,
  rwnd: RwndFacts(
    camera: camera,
    team: team,
    unixStartMs: startMs,
    unixEndMs: startMs + 165000,
    frames: 10,
    durationSec: 165,
    fpgaStart: fpgaStart,
    fpgaEnd: fpgaEnd,
  ),
);

const _t0 = 1760630000000;
const _hourMs = 3600 * 1000;
const _dayMs = 24 * _hourMs;

RobotLogFile _lostClockRewind({int team = 3847, double fpgaEnd = 170.05}) =>
    _rewind(
      '3847/ll/lost.rwnd',
      _t0 - 7 * _dayMs,
      team: team,
      fpgaStart: 5,
      fpgaEnd: fpgaEnd,
      modifiedMs: _t0 + _hourMs,
    );

RobotLogFile _matchLog(
  int number, {
  int? team = 3847,
  int startMs = _t0,
  double lastTs = 300,
  double phaseEnd = 170,
}) => _log(
  '3847/robot/m$number.wpilog',
  _facts(
    team: team,
    matchNumber: number,
    unixStartMs: startMs,
    lastTs: lastTs,
    phases: [WpiPhase('teleop', 20, phaseEnd)],
  ),
);

void main() {
  group('matchFor', () {
    test('keys a match by team, event, type and number', () {
      final m = matchFor(_facts(), 'x.wpilog');
      expect(m.key, '3847-txman1-q15-r1');
      expect(m.label, 'TXMAN1 Q15');
      expect(m.startUnixMs, 1760630020000);
    });

    test('a team override wins and changes the key', () {
      final m = matchFor(_facts(), 'x.wpilog', team: 8515);
      expect(m.team, 8515);
      expect(m.key, '8515-txman1-q15-r1');
    });

    test('falls back to an FMS file name', () {
      final m = matchFor(
        _facts(event: null, matchType: null, matchNumber: null),
        'FRC_20260919_171539_cc_Q4.wpilog',
      );
      expect(m.key, '3847-cc-q4-r1');
    });

    test('a pit-style name files a log that never saw the FMS', () {
      final m = matchFor(
        _facts(team: null, event: null, matchType: null, matchNumber: null),
        '8515_TXMAN1_E2_robot.wpilog',
      );
      expect(m.team, 8515);
      expect(m.matchType, 'Elimination');
      expect(m.key, '8515-txman1-e2-r1');
    });

    test('an FMS test match is labeled, with no key', () {
      final m = matchFor(_facts(matchType: null, matchNumber: 999), 'x.wpilog');
      expect(m.matchType, 'Test');
      expect(m.label, 'TXMAN1 Test 999');
      expect(m.key, isNull);
      expect(m.event, 'TXMAN1');
      expect(m.matchNumber, 999);
    });

    test('a test match replay adds its number to the label', () {
      final m = matchFor(
        _facts(matchType: null, matchNumber: 999, replay: 2),
        'x.wpilog',
      );
      expect(m.label, 'TXMAN1 Test 999 r2');
      expect(m.key, isNull);
    });

    test('a practice log with no match keeps a null key', () {
      final m = matchFor(
        _facts(event: null, matchType: null, matchNumber: null),
        'FRC_20260416_210554.wpilog',
      );
      expect(m.key, isNull);
    });
  });

  group('proposeNames', () {
    test('names a log by its match and a rewind after the log it overlaps', () {
      final log = _log('3847/robot/FRC_1.wpilog', _facts());
      final early = _log(
        '3847/robot/FRC_0.wpilog',
        _facts(matchNumber: 14, unixStartMs: 1760620000000),
      );
      final rw = _rewind('3847/limelight-left/r.rwnd', 1760630100000);
      final files = [log, early, rw];
      proposeNames(files);
      expect(log.name, '3847_TXMAN1_Q15.wpilog');
      expect(early.name, '3847_TXMAN1_Q14.wpilog');
      expect(rw.name, '3847_TXMAN1_Q15_limelight-left.rwnd');
      expect(rw.pairedWith, log.rel);
    });

    test('a rewind does not pair with another team\'s log', () {
      final log = _log('3847/robot/a.wpilog', _facts());
      final rw = _rewind(
        '8515/limelight/r.rwnd',
        1760630100000,
        team: 8515,
        camera: 'limelight',
      );
      proposeNames([log, rw]);
      expect(rw.pairedWith, isNull);
      expect(rw.name, '8515_limelight_20251016T155500.rwnd');
    });

    test('test-match logs get a T name and are numbered apart', () {
      final a = _log(
        '3847/robot/a.wpilog',
        _facts(matchType: null, matchNumber: 999),
      );
      final b = _log(
        '3847/robot/b.wpilog',
        _facts(matchType: null, matchNumber: 999, unixStartMs: 1760640000000),
      );
      proposeNames([b, a]);
      expect(a.name, '3847_TXMAN1_T999.wpilog');
      expect(b.name, '3847_TXMAN1_T999_2.wpilog');
    });

    test('two captures from one camera in one match are numbered', () {
      final log = _log('3847/robot/a.wpilog', _facts());
      final a = _rewind('3847/ll/a.rwnd', 1760630010000);
      final b = _rewind('3847/ll/b.rwnd', 1760630050000);
      proposeNames([log, a, b]);
      expect(a.name, '3847_TXMAN1_Q15_limelight-left.rwnd');
      expect(b.name, '3847_TXMAN1_Q15_limelight-left_2.rwnd');
    });

    test('a sent file keeps its name when an earlier capture arrives', () {
      final log = _log('3847/robot/a.wpilog', _facts());
      final sent = _rewind('3847/ll/b.rwnd', 1760630050000);
      proposeNames([log, sent]);
      expect(sent.name, '3847_TXMAN1_Q15_limelight-left.rwnd');
      sent.uploaded = RobotLogUpload(
        at: DateTime.utc(2026),
        name: sent.name,
        matchId: 'm',
        duplicate: false,
      );
      final earlier = _rewind('3847/ll/a.rwnd', 1760630010000);
      proposeNames([log, sent, earlier]);
      expect(sent.name, '3847_TXMAN1_Q15_limelight-left.rwnd');
      expect(sent.isSent, isTrue);
      expect(earlier.name, '3847_TXMAN1_Q15_limelight-left_2.rwnd');
    });

    test('leaves a hand-edited name alone and keeps a replay suffix', () {
      final edited = _log('3847/robot/a.wpilog', _facts())
        ..name = 'mine.wpilog'
        ..nameEdited = true;
      final replay = _log(
        '3847/robot/b.wpilog',
        _facts(matchNumber: 2, replay: 2),
      );
      proposeNames([edited, replay]);
      expect(edited.name, 'mine.wpilog');
      expect(replay.name, '3847_TXMAN1_Q2_R2.wpilog');
    });

    test('a log with no match keeps its own name', () {
      final log = _log(
        '3847/robot/FRC_20260416_210554.wpilog',
        _facts(event: null, matchType: null, matchNumber: null),
      );
      proposeNames([log]);
      expect(log.name, 'FRC_20260416_210554.wpilog');
    });
  });

  group('robot-clock pairing', () {
    test('pairs by the nearest phase end when the wall clock is lost', () {
      final near = _matchLog(15);
      final other = _matchLog(17, startMs: _t0 + 1000, phaseEnd: 170.12);
      final elsewhere = _matchLog(16, startMs: _t0 + 2000, phaseEnd: 100);
      final rw = _lostClockRewind();
      proposeNames([elsewhere, other, near, rw]);
      expect(rw.pairedWith, near.rel);
      expect(rw.name, '3847_TXMAN1_Q15_limelight-left.rwnd');
    });

    test('falls back to start plus duration for a garbage clip end', () {
      final log = _matchLog(15);
      final rw = _lostClockRewind(fpgaEnd: 99999);
      proposeNames([log, rw]);
      expect(rw.pairedWith, log.rel);
    });

    test('ignores a log outside the 3 days before the pull', () {
      final old = _matchLog(15, startMs: _t0 - 4 * _dayMs);
      final later = _matchLog(16, startMs: _t0 + 2 * _hourMs);
      final rw = _lostClockRewind();
      proposeNames([old, later, rw]);
      expect(rw.pairedWith, isNull);
      expect(rw.name, isNot(contains('TXMAN1')));
    });

    test('ignores another team\'s log', () {
      final log = _matchLog(15, team: 8515);
      final rw = _lostClockRewind();
      proposeNames([log, rw]);
      expect(rw.pairedWith, isNull);
    });

    test('ignores a log whose FPGA span ends before the clip', () {
      final log = _matchLog(15, lastTs: 150);
      final rw = _lostClockRewind();
      proposeNames([log, rw]);
      expect(rw.pairedWith, isNull);
    });

    test('ignores a log with no phase end near the clip end', () {
      final log = _matchLog(15, phaseEnd: 171);
      final rw = _lostClockRewind();
      proposeNames([log, rw]);
      expect(rw.pairedWith, isNull);
    });

    test('needs the pull time and FPGA range, and a team', () {
      final log = _matchLog(15);
      final noTime = _rewind(
        '3847/ll/a.rwnd',
        _t0 - 7 * _dayMs,
        fpgaStart: 5,
        fpgaEnd: 170.05,
      );
      final noFpga = _rewind(
        '3847/ll/b.rwnd',
        _t0 - 7 * _dayMs,
        modifiedMs: _t0 + _hourMs,
      );
      final noTeam = _rewind(
        '3847/ll/c.rwnd',
        _t0 - 7 * _dayMs,
        team: null,
        fpgaStart: 5,
        fpgaEnd: 170.05,
        modifiedMs: _t0 + _hourMs,
      );
      proposeNames([log, noTime, noFpga, noTeam]);
      expect(noTime.pairedWith, isNull);
      expect(noFpga.pairedWith, isNull);
      expect(noTeam.pairedWith, isNull);
    });

    test('a wall-clock overlap wins over the robot clock', () {
      final byTime = _matchLog(15, phaseEnd: 100);
      final byPhase = _matchLog(16, startMs: _t0 + _hourMs);
      final rw = _rewind(
        '3847/ll/a.rwnd',
        _t0 + 100000,
        fpgaStart: 5,
        fpgaEnd: 170.05,
        modifiedMs: _t0 + 2 * _hourMs,
      );
      proposeNames([byTime, byPhase, rw]);
      expect(rw.pairedWith, byTime.rel);
    });
  });

  test('clipEnd falls back when the clip end is garbage', () {
    expect(clipEnd(5, 170, 165), 170);
    expect(clipEnd(5, 170.9, 165), 170.9);
    expect(clipEnd(5, 99999, 165), 170);
    expect(clipEnd(5, double.nan, 165), 170);
    expect(clipEnd(5, null, null), isNull);
    expect(clipEnd(5, 170, null), 170);
    expect(clipEnd(null, 170, 165), isNull);
  });

  test('phaseEndDelta is the nearest end within 0.1 s', () {
    final phases = [WpiPhase('auto', 0, 15), WpiPhase('teleop', 20, 170)];
    expect(phaseEndDelta(phases, 15.05), closeTo(0.05, 1e-9));
    expect(phaseEndDelta(phases, 169.99), closeTo(0.01, 1e-9));
    expect(phaseEndDelta(phases, 100), isNull);
    expect(phaseEndDelta(phases, null), isNull);
    expect(phaseEndDelta(const [], 15), isNull);
  });

  test('isSent tracks the name it was sent under', () {
    final f = _log('3847/robot/a.wpilog', _facts())
      ..name = 'a.wpilog'
      ..uploaded = RobotLogUpload(
        at: DateTime.utc(2026),
        name: 'a.wpilog',
        matchId: 'm1',
        duplicate: false,
      );
    expect(f.isSent, isTrue);
    f.name = 'b.wpilog';
    expect(f.isSent, isFalse);
  });

  test('round-trips the robot-clock fields', () {
    final f = _rewind(
      '3847/ll/a.rwnd',
      _t0,
      fpgaStart: 5,
      fpgaEnd: 170.05,
      modifiedMs: _t0,
    );
    final back = RobotLogFile.fromJson(f.toJson());
    expect(back.modifiedMs, _t0);
    expect(back.rwnd!.fpgaStart, 5);
    expect(back.rwnd!.fpgaEnd, 170.05);
    expect(back.toJson(), f.toJson());
  });

  test('round-trips through JSON', () {
    final f = _rewind('3847/ll/a.rwnd', 1760630010000)
      ..name = 'x.rwnd'
      ..nameEdited = true
      ..team = 8515
      ..teamEdited = true;
    final back = RobotLogFile.fromJson(f.toJson());
    expect(back.toJson(), f.toJson());
  });
}
