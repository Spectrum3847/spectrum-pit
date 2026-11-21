import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class WpiLogBuilder {
  final _b = BytesBuilder();
  final _ids = <String, int>{};

  WpiLogBuilder() {
    _b
      ..add(ascii.encode('WPILOG'))
      ..add([0x00, 0x01])
      ..add(_u32(0));
  }

  static List<int> _u32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

  void _record(int id, int tsUs, List<int> payload) {
    _b
      ..addByte(0x7f)
      ..add(_u32(id))
      ..add(_u32(payload.length))
      ..add(
        (ByteData(8)..setUint64(0, tsUs, Endian.little)).buffer.asUint8List(),
      )
      ..add(payload);
  }

  void start(String name, String type, {int tsUs = 0}) {
    final id = _ids[name] = _ids.length + 1;
    final p = BytesBuilder()
      ..addByte(0)
      ..add(_u32(id));
    for (final s in [name, type, '']) {
      final e = utf8.encode(s);
      p
        ..add(_u32(e.length))
        ..add(e);
    }
    _record(0, tsUs, p.takeBytes());
  }

  void value(String name, double tSec, Object v) {
    final tsUs = (tSec * 1e6).round();
    final List<int> payload = switch (v) {
      bool b => [b ? 1 : 0],
      int i => (ByteData(
        8,
      )..setInt64(0, i, Endian.little)).buffer.asUint8List(),
      double d => (ByteData(
        8,
      )..setFloat64(0, d, Endian.little)).buffer.asUint8List(),
      String s => utf8.encode(s),
      _ => throw ArgumentError(v),
    };
    _record(_ids[name]!, tsUs, payload);
  }

  Uint8List build() => _b.toBytes();
}

List<File> writeRecordingParts(
  Directory dir, {
  int frames = 3,
  bool withIdx1 = true,
  String base = 'rec1',
}) {
  List<int> u32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
  List<int> chunk(String id, List<int> data) => [
    ...ascii.encode(id),
    ...u32(data.length),
    ...data,
    if (data.length.isOdd) 0,
  ];
  List<int> list(String type, List<int> body) => [
    ...ascii.encode('LIST'),
    ...u32(body.length + 4),
    ...ascii.encode(type),
    ...body,
  ];

  final avih = List<int>.filled(56, 0);
  avih.setRange(0, 4, u32(33333));
  avih.setRange(32, 36, u32(640));
  avih.setRange(36, 40, u32(480));
  final jpegs = [
    for (var i = 0; i < frames; i++)
      [0xff, 0xd8, ...List<int>.filled(10 + i, i), 0xff, 0xd9],
  ];
  final movi = <int>[];
  final idx = <int>[];
  for (final j in jpegs) {
    idx
      ..addAll(ascii.encode('00dc'))
      ..addAll(u32(0x10))
      ..addAll(u32(4 + movi.length))
      ..addAll(u32(j.length));
    movi.addAll(chunk('00dc', j));
  }
  final body = [
    ...ascii.encode('AVI '),
    ...list('hdrl', chunk('avih', avih)),
    ...list('movi', movi),
    if (withIdx1) ...chunk('idx1', idx),
  ];
  final avi = [...ascii.encode('RIFF'), ...u32(body.length), ...body];

  final lines = [
    jsonEncode({
      'version': 1,
      'fps': 30,
      'width': 640,
      'height': 480,
      'frameCount': frames,
      'durationSeconds': frames / 30,
    }),
    for (var i = 0; i < frames; i++)
      jsonEncode({
        'frameIndex': i,
        'results': {
          'ts_nt': 100000000 + i * 33333,
          'ts_sys': 1760630000000000 + i * 33333,
          'cl': 5.5,
          'tl': 10.25,
          'v': i.isEven ? 1 : 0,
          'Fiducial': [
            {'fID': 7 + i},
          ],
          'botpose_orb_wpiblue': [1.23456, 2.5, 0, 0, 0, 90.0],
          'botpose_wpiblue': [0, 0, 0, 0, 0, 0],
          'hw': {'temp': 40.1234, 'cpu': 12},
        },
      }),
  ];
  const boot =
      'Oct 16 10:00:00 limelight-left systemd[1]: started\n'
      'Oct 16 10:00:01 limelight-left net: address 10.38.47.11\n';

  final out = [
    File('${dir.path}/$base.avi')..writeAsBytesSync(avi),
    File('${dir.path}/${base}_manifest.jsonl')
      ..writeAsStringSync('${lines.join('\n')}\n'),
    File('${dir.path}/${base}_bootlog.txt.gz')
      ..writeAsBytesSync(gzip.encode(utf8.encode(boot))),
  ];
  return out;
}

Uint8List matchLog({
  int team = 3847,
  String event = 'TXMAN1',
  String matchType = 'Qualification',
  int matchNumber = 3,
  int unixAtZeroMs = 1760629990000,
}) {
  final b = WpiLogBuilder()
    ..start('DS:enabled', 'boolean')
    ..start('/Robot/SystemStats/TeamNumber', 'int64')
    ..start('/Robot/Match Data/EventName', 'string')
    ..start('/Robot/Match Data/MatchType', 'string')
    ..start('/Robot/Match Data/MatchNumber', 'int64')
    ..start('systemTime', 'int64');
  b
    ..value('/Robot/Match Data/EventName', 1, '')
    ..value('systemTime', 2, (unixAtZeroMs + 2000) * 1000)
    ..value('/Robot/SystemStats/TeamNumber', 2, team)
    ..value('/Robot/Match Data/EventName', 5, event)
    ..value('/Robot/Match Data/MatchType', 5, matchType)
    ..value('/Robot/Match Data/MatchNumber', 5, matchNumber)
    ..value('DS:enabled', 10, true)
    ..value('DS:enabled', 160, false)
    ..value('systemTime', 200, (unixAtZeroMs + 200000) * 1000);
  return b.build();
}
