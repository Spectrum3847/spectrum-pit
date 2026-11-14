import '../services/wpilog_reader.dart';

enum RobotLogKind {
  wpilog,
  rwnd;

  String get extension => '.$name';
}

class RwndFacts {
  const RwndFacts({
    required this.camera,
    required this.team,
    required this.unixStartMs,
    required this.unixEndMs,
    required this.frames,
    required this.durationSec,
    this.fpgaStart,
    this.fpgaEnd,
  });

  final String? camera;
  final int? team;
  final int? unixStartMs;
  final int? unixEndMs;
  final int frames;
  final double? durationSec;

  final double? fpgaStart;
  final double? fpgaEnd;

  Map<String, dynamic> toJson() => {
    'camera': camera,
    'team': team,
    'unixStartMs': unixStartMs,
    'unixEndMs': unixEndMs,
    'frames': frames,
    'durationSec': durationSec,
    'fpgaStart': fpgaStart,
    'fpgaEnd': fpgaEnd,
  };

  factory RwndFacts.fromJson(Map<String, dynamic> j) => RwndFacts(
    camera: j['camera'] as String?,
    team: j['team'] as int?,
    unixStartMs: j['unixStartMs'] as int?,
    unixEndMs: j['unixEndMs'] as int?,
    frames: j['frames'] as int? ?? 0,
    durationSec: (j['durationSec'] as num?)?.toDouble(),
    fpgaStart: (j['fpgaStart'] as num?)?.toDouble(),
    fpgaEnd: (j['fpgaEnd'] as num?)?.toDouble(),
  );
}

class RobotLogUpload {
  const RobotLogUpload({
    required this.at,
    required this.name,
    required this.matchId,
    required this.duplicate,
  });

  final DateTime at;
  final String name;
  final String? matchId;

  final bool duplicate;

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'name': name,
    'matchId': matchId,
    'duplicate': duplicate,
  };

  factory RobotLogUpload.fromJson(Map<String, dynamic> j) => RobotLogUpload(
    at: DateTime.parse(j['at'] as String),
    name: j['name'] as String,
    matchId: j['matchId'] as String?,
    duplicate: j['duplicate'] as bool? ?? false,
  );
}

class RobotLogFile {
  RobotLogFile({
    required this.rel,
    required this.kind,
    required this.size,
    this.sourceTeam,
    this.wpilog,
    this.rwnd,
    String? name,
    this.nameEdited = false,
    this.team,
    this.teamEdited = false,
    this.uploaded,
    this.modifiedMs,
  }) : name = name ?? rel.split('/').last;

  final String rel;
  final RobotLogKind kind;
  final int size;

  final int? sourceTeam;
  final WpiLogFacts? wpilog;
  final RwndFacts? rwnd;

  String name;
  bool nameEdited;

  int? team;
  bool teamEdited;
  RobotLogUpload? uploaded;

  final int? modifiedMs;

  String? pairedWith;

  String get original => rel.split('/').last;

  int? get recordedUnixMs => wpilog?.unixStartMs ?? rwnd?.unixStartMs;

  bool get isSent => uploaded != null && uploaded!.name == name;

  Map<String, dynamic> toJson() => {
    'rel': rel,
    'kind': kind.name,
    'size': size,
    'sourceTeam': sourceTeam,
    'wpilog': wpilog?.toJson(),
    'rwnd': rwnd?.toJson(),
    'name': name,
    'nameEdited': nameEdited,
    'team': team,
    'teamEdited': teamEdited,
    'uploaded': uploaded?.toJson(),
    'modifiedMs': modifiedMs,
  };

  factory RobotLogFile.fromJson(Map<String, dynamic> j) {
    final wpilog = j['wpilog'] as Map<String, dynamic>?;
    final rwnd = j['rwnd'] as Map<String, dynamic>?;
    final uploaded = j['uploaded'] as Map<String, dynamic>?;
    return RobotLogFile(
      rel: j['rel'] as String,
      kind: RobotLogKind.values.byName(j['kind'] as String),
      size: j['size'] as int,
      sourceTeam: j['sourceTeam'] as int?,
      wpilog: wpilog == null ? null : WpiLogFacts.fromJson(wpilog),
      rwnd: rwnd == null ? null : RwndFacts.fromJson(rwnd),
      name: j['name'] as String?,
      nameEdited: j['nameEdited'] as bool? ?? false,
      team: j['team'] as int?,
      teamEdited: j['teamEdited'] as bool? ?? false,
      uploaded: uploaded == null ? null : RobotLogUpload.fromJson(uploaded),
      modifiedMs: j['modifiedMs'] as int?,
    );
  }
}

class LogMatch {
  const LogMatch({
    required this.key,
    required this.label,
    required this.team,
    required this.event,
    required this.matchType,
    required this.matchNumber,
    required this.replay,
    required this.alliance,
    required this.station,
    required this.startUnixMs,
  });

  final String? key;
  final String? label;
  final int? team;
  final String? event;
  final String? matchType;
  final int? matchNumber;
  final int? replay;
  final String? alliance;
  final int? station;
  final int? startUnixMs;

  String? get letter => matchType == null
      ? null
      : (_matchTypeLetter[matchType] ?? matchType!.substring(0, 1));

  Map<String, dynamic> toJson() => {
    'key': key,
    'team': team,
    'label': label,
    'event': event,
    'matchType': matchType,
    'matchNumber': matchNumber,
    'replay': replay,
    'alliance': alliance,
    'station': station,
    'startUnixMs': startUnixMs,
  };
}

const _matchTypeLetter = {
  'Practice': 'P',
  'Qualification': 'Q',
  'Elimination': 'E',
};
const _letterMatchType = {
  'P': 'Practice',
  'Q': 'Qualification',
  'E': 'Elimination',
};

final _fmsName = RegExp(
  r'FRC_\d{8}_\d{6}_([A-Za-z0-9]+)_([PQE])(\d+)\.wpilog$',
  caseSensitive: false,
);
final _akitName = RegExp(
  r'akit_[\d-]+_[\d-]+_([A-Za-z0-9]+)_([PQE])(\d+)\.wpilog$',
  caseSensitive: false,
);

final _pitName = RegExp(
  r'^(\d{2,5})_([A-Za-z0-9]+)_([PQE])(\d+)(?:_[^/\\]*)?\.wpilog$',
  caseSensitive: false,
);
final _pitNameTeam = RegExp(
  r'^(\d{2,5})_[A-Za-z0-9]+_[PQE]\d+',
  caseSensitive: false,
);

LogMatch matchFor(
  WpiLogFacts facts,
  String fileName, {
  int? team,
  int? fallbackTeam,
}) {
  final nameTeam = _pitNameTeam.firstMatch(fileName);
  final resolvedTeam =
      team ??
      facts.team ??
      fallbackTeam ??
      (nameTeam == null ? null : int.parse(nameTeam[1]!));
  var event = facts.event;
  var matchType = facts.matchType;
  var matchNumber = facts.matchNumber;
  final fm = _fmsName.firstMatch(fileName) ?? _akitName.firstMatch(fileName);
  final named = fm == null ? _pitName.firstMatch(fileName) : null;
  final from = fm ?? named;
  if (from != null) {
    final g = fm != null ? 1 : 2;
    event ??= from[g]!.toUpperCase();
    matchType ??= _letterMatchType[from[g + 1]!.toUpperCase()];
    matchNumber ??= int.parse(from[g + 2]!);
  }

  String? key;
  String? label;
  final replay = facts.replay;
  if (event != null && matchType != null && matchNumber != null) {
    final letter = _matchTypeLetter[matchType] ?? matchType.substring(0, 1);
    label =
        '$event $letter$matchNumber${(replay ?? 0) > 1 ? ' (replay $replay)' : ''}';

    key = '${resolvedTeam ?? 0}-$event-$letter$matchNumber-r${replay ?? 1}'
        .toLowerCase();
  } else if (facts.fmsAttached && event != null && matchNumber != null) {
    matchType = 'Test';
    label = '$event Test $matchNumber${replay == null ? '' : ' r$replay'}';
  }
  return LogMatch(
    key: key,
    label: label,
    team: resolvedTeam,
    event: event,
    matchType: matchType,
    matchNumber: matchNumber,
    replay: replay,
    alliance: facts.alliance,
    station: facts.station,
    startUnixMs: facts.toUnixMs(facts.matchStart),
  );
}

const _clipEndSlackS = 0.1;
const _robotClockWindowMs = 3 * 24 * 3600 * 1000;

double? clipEnd(double? start, double? end, double? durationSec) {
  if (start == null || !start.isFinite) return null;
  final byDuration = durationSec != null && durationSec.isFinite
      ? start + durationSec
      : null;
  if (end == null ||
      !end.isFinite ||
      (byDuration != null && end > byDuration + 1)) {
    return byDuration;
  }
  return end;
}

double? phaseEndDelta(List<WpiPhase> phases, double? end) {
  if (end == null) return null;
  double? best;
  for (final p in phases) {
    final d = (p.end - end).abs();
    if (d.isFinite && d <= _clipEndSlackS && (best == null || d < best)) {
      best = d;
    }
  }
  return best;
}

RobotLogFile? _pairByRobotClock(
  RobotLogFile rewind,
  int? team,
  List<RobotLogFile> logs,
) {
  final r = rewind.rwnd;
  final pulled = rewind.modifiedMs;
  final end = r == null ? null : clipEnd(r.fpgaStart, r.fpgaEnd, r.durationSec);
  if (team == null || pulled == null || end == null) return null;
  RobotLogFile? best;
  var bestDelta = double.infinity;
  for (final l in logs) {
    final facts = l.wpilog!;
    final start = facts.unixStartMs;
    if (start == null ||
        start > pulled ||
        start < pulled - _robotClockWindowMs ||
        facts.firstTs > end ||
        facts.lastTs < end ||
        matchFor(facts, l.original, fallbackTeam: l.sourceTeam).team != team) {
      continue;
    }
    final d = phaseEndDelta(facts.phases, end);
    if (d != null && d < bestDelta) {
      best = l;
      bestDelta = d;
    }
  }
  return best;
}

final _unsafe = RegExp(r'[^A-Za-z0-9._-]+');

String safeLogName(String s) => s.replaceAll(_unsafe, '_');

String _matchPart(LogMatch m, int? team) =>
    '${m.team ?? team ?? 0}_${safeLogName(m.event!).toUpperCase()}_'
    '${m.letter ?? 'M'}${m.matchNumber}';

void proposeNames(List<RobotLogFile> files, {RobotLogFile? reset}) {
  bool fixed(RobotLogFile f) => f != reset && (f.nameEdited || f.isSent);
  final logs = files.where((f) => f.wpilog != null).toList();
  for (final f in files) {
    if (f.kind == RobotLogKind.wpilog) {
      final facts = f.wpilog;
      if (fixed(f) || facts == null) continue;
      final m = matchFor(facts, f.original, fallbackTeam: f.sourceTeam);
      f.name = m.event != null && m.matchNumber != null
          ? '${_matchPart(m, null)}${(m.replay ?? 0) > 1 ? '_R${m.replay}' : ''}.wpilog'
          : f.original;
      continue;
    }
    final r = f.rwnd;
    final team = r?.team ?? f.team ?? f.sourceTeam;
    RobotLogFile? best;
    LogMatch? bestMatch;
    var bestOverlap = double.negativeInfinity;
    final a = r?.unixStartMs;
    if (a != null) {
      final b = r!.unixEndMs ?? a;
      for (final l in logs) {
        final m = matchFor(l.wpilog!, l.original, fallbackTeam: l.sourceTeam);
        if (team != null && m.team != null && m.team != team) continue;
        final la = l.wpilog!.unixStartMs;
        final lb = l.wpilog!.unixEndMs;
        if (la == null || lb == null) continue;
        final overlap = (b < lb ? b : lb) - (a > la ? a : la);
        if (overlap > bestOverlap && overlap > -60000) {
          best = l;
          bestMatch = m;
          bestOverlap = overlap.toDouble();
        }
      }
    }
    if (best == null) {
      best = _pairByRobotClock(f, team, logs);
      if (best != null) {
        bestMatch = matchFor(
          best.wpilog!,
          best.original,
          fallbackTeam: best.sourceTeam,
        );
      }
    }
    f.pairedWith = best?.rel;
    if (fixed(f)) continue;
    final cam = safeLogName(r?.camera ?? 'limelight');
    if (bestMatch != null &&
        bestMatch.event != null &&
        bestMatch.matchNumber != null) {
      f.name = '${_matchPart(bestMatch, team)}_$cam.rwnd';
    } else {
      final when = a == null
          ? ''
          : '_${DateTime.fromMillisecondsSinceEpoch(a, isUtc: true).toIso8601String().replaceAll(RegExp(r'[-:]'), '').substring(0, 15)}';
      f.name = '${team ?? 0}_$cam$when.rwnd';
    }
  }

  final taken = {
    for (final f in files)
      if (fixed(f)) f.name,
  };
  final ordered = [...files]
    ..sort((x, y) => (x.recordedUnixMs ?? 0).compareTo(y.recordedUnixMs ?? 0));
  for (final f in ordered) {
    if (fixed(f)) continue;
    final base = f.name;
    for (var n = 2; taken.contains(f.name); n++) {
      f.name = base.replaceFirstMapped(
        RegExp(r'(\.\w+)$'),
        (m) => '_$n${m[1]}',
      );
    }
    taken.add(f.name);
  }
}
