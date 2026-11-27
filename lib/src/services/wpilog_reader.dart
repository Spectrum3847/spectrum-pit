import 'dart:convert';
import 'dart:typed_data';

class WpiPhase {
  const WpiPhase(this.phase, this.start, this.end);

  final String phase;

  final double start;
  final double end;

  Map<String, dynamic> toJson() => {'phase': phase, 'start': start, 'end': end};

  factory WpiPhase.fromJson(Map<String, dynamic> j) => WpiPhase(
    j['phase'] as String,
    (j['start'] as num).toDouble(),
    (j['end'] as num).toDouble(),
  );
}

class WpiLogFacts {
  const WpiLogFacts({
    required this.layout,
    required this.team,
    required this.event,
    required this.matchType,
    required this.matchNumber,
    required this.replay,
    required this.alliance,
    required this.station,
    required this.fmsAttached,
    required this.firstTs,
    required this.lastTs,
    required this.unixOffset,
    required this.matchStart,
    required this.enabledSeconds,
    this.phases = const [],
  });

  final String layout;
  final int? team;
  final String? event;
  final String? matchType;
  final int? matchNumber;
  final int? replay;
  final String? alliance;
  final int? station;
  final bool fmsAttached;

  final double firstTs;
  final double lastTs;

  final double? unixOffset;

  final double? matchStart;
  final double enabledSeconds;
  final List<WpiPhase> phases;

  int? toUnixMs(double? t) => t == null || unixOffset == null
      ? null
      : ((t + unixOffset!) * 1000).round();

  int? get unixStartMs => toUnixMs(firstTs);
  int? get unixEndMs => toUnixMs(lastTs);

  Map<String, dynamic> toJson() => {
    'layout': layout,
    'team': team,
    'event': event,
    'matchType': matchType,
    'matchNumber': matchNumber,
    'replay': replay,
    'alliance': alliance,
    'station': station,
    'fmsAttached': fmsAttached,
    'firstTs': firstTs,
    'lastTs': lastTs,
    'unixOffset': unixOffset,
    'matchStart': matchStart,
    'enabledSeconds': enabledSeconds,
    'phases': [for (final p in phases) p.toJson()],
  };

  factory WpiLogFacts.fromJson(Map<String, dynamic> j) => WpiLogFacts(
    layout: j['layout'] as String? ?? 'wpilib',
    team: j['team'] as int?,
    event: j['event'] as String?,
    matchType: j['matchType'] as String?,
    matchNumber: j['matchNumber'] as int?,
    replay: j['replay'] as int?,
    alliance: j['alliance'] as String?,
    station: j['station'] as int?,
    fmsAttached: j['fmsAttached'] as bool? ?? false,
    firstTs: (j['firstTs'] as num?)?.toDouble() ?? 0,
    lastTs: (j['lastTs'] as num?)?.toDouble() ?? 0,
    unixOffset: (j['unixOffset'] as num?)?.toDouble(),
    matchStart: (j['matchStart'] as num?)?.toDouble(),
    enabledSeconds: (j['enabledSeconds'] as num?)?.toDouble() ?? 0,
    phases: [
      for (final p in (j['phases'] as List?) ?? const [])
        WpiPhase.fromJson((p as Map).cast<String, dynamic>()),
    ],
  );
}

class WpiLogFormatException implements Exception {
  const WpiLogFormatException();
  @override
  String toString() => 'not a WPILib .wpilog file';
}

typedef _Series = List<(double, Object)>;

const _matchDataKeys = [
  'EventName',
  'MatchType',
  'MatchNumber',
  'ReplayNumber',
  'Alliance',
  'Station',
  'AllianceStation',
  'FMSAttached',
];

const _wpiMatchTypes = ['None', 'Practice', 'Qualification', 'Elimination'];

bool _wanted(String name) {
  switch (name) {
    case 'DS:enabled':
    case 'DS:autonomous':
    case '/DriverStation/Enabled':
    case '/DriverStation/RobotMode':
    case 'systemTime':
    case '/SystemStats/EpochTimeMicros':
      return true;
  }
  if (name.endsWith('SystemStats/TeamNumber')) return true;
  for (final k in _matchDataKeys) {
    if (name.endsWith('Match Data/$k') || name == '/DriverStation/$k') {
      return true;
    }
  }
  return false;
}

WpiLogFacts readWpiLogFacts(Uint8List bytes) {
  final log = _parse(bytes);
  return _facts(log);
}

class _Log {
  final channels = <String, _Series>{};
  final names = <String>[];
  double? firstTs;
  double? lastTs;

  _Series channel(String name) => channels[name] ?? const [];
  bool has(String name) => channel(name).isNotEmpty;

  _Series ch(String name) {
    if (has('/Robot/$name')) return channel('/Robot/$name');
    for (final full in names) {
      if (full == name || full.endsWith('/$name')) return channel(full);
    }
    return const [];
  }
}

_Log _parse(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final end = bytes.length;
  if (end < 12 ||
      ascii.decode(bytes.sublist(0, 6), allowInvalid: true) != 'WPILOG') {
    throw const WpiLogFormatException();
  }
  final log = _Log();
  final entries = <int, (String, String)>{};
  var pos = 12 + view.getUint32(8, Endian.little);

  int readUint(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v |= bytes[pos++] << (8 * i);
    }
    return v;
  }

  String readString() {
    final len = readUint(4);
    final s = utf8.decode(bytes.sublist(pos, pos + len), allowMalformed: true);
    pos += len;
    return s;
  }

  try {
    while (pos < end) {
      final h = bytes[pos++];
      final idLen = (h & 0x3) + 1;
      final sizeLen = ((h >> 2) & 0x3) + 1;

      final tsLen = ((h >> 4) & 0x7) + 1;
      if (pos + idLen + sizeLen + tsLen > end) break;
      final id = readUint(idLen);
      final size = readUint(sizeLen);
      final tSec = readUint(tsLen) / 1e6;
      if (pos + size > end) break;
      final start = pos;
      log.firstTs ??= tSec;
      log.lastTs = tSec;

      if (id == 0) {
        if (size > 0 && bytes[pos] == 0) {
          pos += 1;
          final entryId = readUint(4);
          final name = readString();
          final type = readString();
          entries[entryId] = (name, type);
          if (!log.channels.containsKey(name)) {
            log.names.add(name);
            if (_wanted(name)) log.channels[name] = [];
          }
        }
      } else {
        final entry = entries[id];
        final series = entry == null ? null : log.channels[entry.$1];
        if (series != null) {
          final value = _decode(entry!.$2, view, bytes, start, size);
          if (value != null) series.add((tSec, value));
        }
      }
      pos = start + size;
    }
  } on RangeError {}
  return log;
}

Object? _decode(String type, ByteData view, Uint8List bytes, int at, int size) {
  switch (type) {
    case 'double':
      return size >= 8 ? view.getFloat64(at, Endian.little) : null;
    case 'float':
      return size >= 4 ? view.getFloat32(at, Endian.little) : null;
    case 'int64':
      return size >= 8 ? view.getInt64(at, Endian.little) : null;
    case 'boolean':
      return size >= 1 ? bytes[at] != 0 : null;
    case 'string':
    case 'json':
      return utf8.decode(bytes.sublist(at, at + size), allowMalformed: true);
  }
  return null;
}

T? _lastWhere<T>(_Series s, bool Function(Object v) ok) {
  for (var i = s.length - 1; i >= 0; i--) {
    final v = s[i].$2;
    if (ok(v)) return v as T;
  }
  return null;
}

int? _positiveInt(_Series s, {int max = 1 << 31}) {
  final v = _lastWhere<num>(s, (v) => v is num && v > 0 && v < max);
  return v?.toInt();
}

WpiLogFacts _facts(_Log log) {
  final ak = log.has('/DriverStation/Enabled') && !log.has('DS:enabled');
  _Series md(String k) =>
      ak ? log.channel('/DriverStation/$k') : log.ch('Match Data/$k');

  final event = _lastWhere<String>(
    md('EventName'),
    (v) => v is String && v.trim().isNotEmpty,
  );
  String? matchType;
  if (ak) {
    final n = _positiveInt(md('MatchType'), max: _wpiMatchTypes.length);
    matchType = n == null ? null : _wpiMatchTypes[n];
  } else {
    matchType = _lastWhere<String>(
      md('MatchType'),
      (v) => v is String && v.isNotEmpty && v != 'None',
    );
  }
  String? alliance;
  int? station;
  if (ak) {
    final id = _lastWhere<num>(
      md('AllianceStation'),
      (v) => v is num && v >= 1 && v <= 6,
    )?.toInt();
    alliance = id == null ? null : (id <= 3 ? 'Red' : 'Blue');
    station = id == null ? null : (id - 1) % 3 + 1;
  } else {
    alliance = _lastWhere<String>(
      md('Alliance'),
      (v) => v == 'Red' || v == 'Blue',
    );
    station = _positiveInt(md('Station'));
  }

  final phases = _phases(log);

  return WpiLogFacts(
    layout: ak ? 'advantagekit' : 'wpilib',
    team: _positiveInt(log.ch('SystemStats/TeamNumber'), max: 100000),
    event: event,
    matchType: matchType,
    matchNumber: _positiveInt(md('MatchNumber')),
    replay: _positiveInt(md('ReplayNumber')),
    alliance: alliance,
    station: station,
    fmsAttached: md('FMSAttached').any((e) => e.$2 == true),
    firstTs: _round(log.firstTs ?? 0, 1000),
    lastTs: _round(log.lastTs ?? 0, 1000),
    unixOffset: _unixOffset(log),
    matchStart: phases.isEmpty ? null : _round(phases.first.start, 1000),
    enabledSeconds: _round(
      phases.fold<double>(0, (a, p) => a + (p.end - p.start)),
      10,
    ),
    phases: phases,
  );
}

List<WpiPhase> _phases(_Log log) {
  final enabled = log.has('DS:enabled')
      ? log.channel('DS:enabled')
      : log.channel('/DriverStation/Enabled');
  final lastTs = log.lastTs ?? 0;
  final spans = <(double, double)>[];
  double? open;
  for (final (t, v) in enabled) {
    if (v == true && open == null) {
      open = t;
    } else if (v != true && open != null) {
      spans.add((open, t));
      open = null;
    }
  }
  if (open != null) spans.add((open, lastTs));

  final auto = _autonomous(log);
  final phases = <WpiPhase>[];
  for (final (s, rawEnd) in spans) {
    final e = rawEnd < lastTs ? rawEnd : lastTs;
    if (e > s || (e == s && s <= lastTs)) {
      final isAuto = _valueAt(auto, s + 1e-6) == true;
      phases.add(WpiPhase(isAuto ? 'auto' : 'teleop', s, e));
    }
  }
  return phases;
}

_Series _autonomous(_Log log) {
  if (log.has('DS:autonomous')) return log.channel('DS:autonomous');
  return [
    for (final (t, v) in log.channel('/DriverStation/RobotMode'))
      (t, '$v'.toUpperCase().startsWith('AUTO')),
  ];
}

Object? _valueAt(_Series s, double t) {
  var lo = 0;
  var hi = s.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (s[mid].$1 <= t) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found < 0 ? null : s[found].$2;
}

double? _unixOffset(_Log log) {
  final source = log.has('systemTime')
      ? log.channel('systemTime')
      : log.channel('/SystemStats/EpochTimeMicros');
  final d = [
    for (final (t, v) in source)
      if (v is num && v > 1.5e15) v / 1e6 - t,
  ]..sort();
  return d.isEmpty ? null : d[d.length >> 1];
}

double _round(double v, int scale) => (v * scale).round() / scale;
