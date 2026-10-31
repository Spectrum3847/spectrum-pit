import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

const _chunk = 4 * 1024 * 1024;

int _crcOf(File file) {
  var c = 0xffffffff;
  final raf = file.openSync();
  try {
    while (true) {
      final buf = raf.readSync(_chunk);
      if (buf.isEmpty) break;
      for (final b in buf) {
        c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
      }
    }
  } finally {
    raf.closeSync();
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}

void writeStoredZip(File out, List<(String, File)> members) {
  final tmp = File('${out.path}.part');
  final raf = tmp.openSync(mode: FileMode.write);
  final central = BytesBuilder();
  var offset = 0;
  void write(List<int> b) {
    raf.writeFromSync(b);
    offset += b.length;
  }

  try {
    for (final (name, file) in members) {
      final size = file.lengthSync();
      if (size >= 0xffffffff) {
        throw StateError('$name is too large for a .rwnd');
      }
      final crc = _crcOf(file);
      final nameBytes = utf8.encode(name);
      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 10, Endian.little)
        ..setUint16(6, 0x0800, Endian.little)
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, size, Endian.little)
        ..setUint32(22, size, Endian.little)
        ..setUint16(26, nameBytes.length, Endian.little);
      final at = offset;
      write(local.buffer.asUint8List());
      write(nameBytes);
      final src = file.openSync();
      try {
        while (true) {
          final buf = src.readSync(_chunk);
          if (buf.isEmpty) break;
          write(buf);
        }
      } finally {
        src.closeSync();
      }
      final cd = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 10, Endian.little)
        ..setUint16(8, 0x0800, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, size, Endian.little)
        ..setUint32(24, size, Endian.little)
        ..setUint16(28, nameBytes.length, Endian.little)
        ..setUint32(42, at, Endian.little);
      central
        ..add(cd.buffer.asUint8List())
        ..add(nameBytes);
    }
    final cdStart = offset;
    write(central.takeBytes());
    final eocd = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, members.length, Endian.little)
      ..setUint16(10, members.length, Endian.little)
      ..setUint32(12, offset - cdStart, Endian.little)
      ..setUint32(16, cdStart, Endian.little);
    write(eocd.buffer.asUint8List());
  } on Object {
    raf.closeSync();
    tmp.deleteSync();
    rethrow;
  }
  raf.closeSync();
  tmp.renameSync(out.path);
}

class _Reader {
  _Reader(File file) : _raf = file.openSync(), size = file.lengthSync();
  final RandomAccessFile _raf;
  final int size;

  Uint8List read(int offset, int length) {
    _raf.setPositionSync(offset);
    return _raf.readSync(length);
  }

  void close() => _raf.closeSync();
}

class _ZipEntry {
  _ZipEntry(this.name, this.method, this.compSize, this.size, this.dataOffset);
  final String name;
  final int method;
  final int compSize;
  final int size;
  final int dataOffset;
}

ByteData _dv(Uint8List u) => ByteData.sublistView(u);
String _fourcc(Uint8List u, int o) => String.fromCharCodes(u, o, o + 4);

List<_ZipEntry> _readZip(_Reader r) {
  final tailLen = r.size < 66 * 1024 ? r.size : 66 * 1024;
  final tail = r.read(r.size - tailLen, tailLen);
  var eocd = -1;
  for (var i = tail.length - 22; i >= 0; i--) {
    if (tail[i] == 0x50 &&
        tail[i + 1] == 0x4b &&
        tail[i + 2] == 0x05 &&
        tail[i + 3] == 0x06) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const FormatException('not a zip file');
  final tv = _dv(tail);
  final count = tv.getUint16(eocd + 10, Endian.little);
  final cdSize = tv.getUint32(eocd + 12, Endian.little);
  final cdOffset = tv.getUint32(eocd + 16, Endian.little);
  if (cdOffset == 0xffffffff || count == 0xffff) {
    throw const FormatException('zip64 .rwnd files are not supported');
  }
  final cd = r.read(cdOffset, cdSize);
  final v = _dv(cd);
  final out = <_ZipEntry>[];
  var p = 0;
  for (var i = 0; i < count && p + 46 <= cd.length; i++) {
    if (v.getUint32(p, Endian.little) != 0x02014b50) break;
    final method = v.getUint16(p + 10, Endian.little);
    final compSize = v.getUint32(p + 20, Endian.little);
    final size = v.getUint32(p + 24, Endian.little);
    final nameLen = v.getUint16(p + 28, Endian.little);
    final extraLen = v.getUint16(p + 30, Endian.little);
    final commentLen = v.getUint16(p + 32, Endian.little);
    final localOffset = v.getUint32(p + 42, Endian.little);
    final name = utf8.decode(cd.sublist(p + 46, p + 46 + nameLen));

    final lh = _dv(r.read(localOffset, 30));
    if (lh.getUint32(0, Endian.little) != 0x04034b50) {
      throw FormatException('bad local header for $name');
    }
    final data =
        localOffset +
        30 +
        lh.getUint16(26, Endian.little) +
        lh.getUint16(28, Endian.little);
    out.add(_ZipEntry(name, method, compSize, size, data));
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

Uint8List _memberBytes(_Reader r, _ZipEntry e) {
  final raw = r.read(e.dataOffset, e.compSize);
  if (e.method == 0) return raw;
  if (e.method == 8) {
    return Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
  }
  throw FormatException('${e.name}: unsupported zip compression ${e.method}');
}

class _AviIndex {
  _AviIndex(this.width, this.height, this.usPerFrame, this.offsets, this.sizes);
  final int width;
  final int height;
  final int usPerFrame;
  final List<int> offsets;
  final List<int> sizes;
}

int _findChunk(Uint8List u, int from, int to, String id) {
  var p = from;
  while (p + 8 <= to) {
    if (_fourcc(u, p) == id) return p;
    final len = _dv(u).getUint32(p + 4, Endian.little);
    p += 8 + len + (len & 1);
  }
  return -1;
}

bool _isFrame(String id) => id.endsWith('dc') || id.endsWith('db');

_AviIndex _indexAvi(_Reader r, int base, int size) {
  final head = r.read(base, size < 64 * 1024 ? size : 64 * 1024);
  if (_fourcc(head, 0) != 'RIFF' || _fourcc(head, 8) != 'AVI ') {
    throw const FormatException('not an AVI file');
  }
  final hv = _dv(head);
  var width = 0, height = 0, usPerFrame = 0;
  var p = 12;
  (int, int)? movi;
  (int, int)? idx1;
  while (p + 8 <= size) {
    final hdr = p + 12 <= head.length
        ? Uint8List.sublistView(head, p, p + 12)
        : r.read(base + p, 12);
    if (hdr.length < 8) break;
    final id = _fourcc(hdr, 0);
    final len = _dv(hdr).getUint32(4, Endian.little);
    final listType = hdr.length >= 12 ? _fourcc(hdr, 8) : '';
    if (id == 'LIST' && listType == 'hdrl' && p + 8 + len <= head.length) {
      final a = _findChunk(head, p + 12, p + 8 + len, 'avih');
      if (a >= 0) {
        usPerFrame = hv.getUint32(a + 8, Endian.little);
        width = hv.getUint32(a + 8 + 32, Endian.little);
        height = hv.getUint32(a + 8 + 36, Endian.little);
      }
    } else if (id == 'LIST' && listType == 'movi') {
      movi = (p + 8, p + 8 + len);
    } else if (id == 'idx1') {
      idx1 = (p + 8, len);
    }
    p += 8 + len + (len & 1);
  }
  if (movi == null) throw const FormatException('AVI has no movi list');

  final offsets = <int>[];
  final sizes = <int>[];
  if (idx1 != null) {
    final ix = r.read(base + idx1.$1, idx1.$2);
    final v = _dv(ix);

    var rel = true;
    for (var i = 0; i + 16 <= ix.length; i += 16) {
      if (!_isFrame(_fourcc(ix, i))) continue;
      final off = v.getUint32(i + 8, Endian.little);
      final probe = r.read(base + movi.$1 + off, 4);
      rel = probe.length == 4 && _fourcc(probe, 0) == _fourcc(ix, i);
      break;
    }
    for (var i = 0; i + 16 <= ix.length; i += 16) {
      if (!_isFrame(_fourcc(ix, i))) continue;
      final off = v.getUint32(i + 8, Endian.little);
      offsets.add(base + (rel ? movi.$1 + off : off) + 8);
      sizes.add(v.getUint32(i + 12, Endian.little));
    }
  } else {
    var q = movi.$1 + 4;
    Uint8List? buf;
    var bufAt = 0;
    while (q + 8 <= movi.$2) {
      if (buf == null || q + 8 > bufAt + buf.length) {
        bufAt = q;
        final want = movi.$2 - q;
        buf = r.read(base + q, want < _chunk ? want : _chunk);
        if (buf.length < 8) break;
      }
      final id = _fourcc(buf, q - bufAt);
      final len = _dv(buf).getUint32(q - bufAt + 4, Endian.little);
      if (id == 'LIST') {
        q += 12;
        continue;
      }
      if (_isFrame(id)) {
        offsets.add(base + q + 8);
        sizes.add(len);
      }
      q += 8 + len + (len & 1);
    }
  }
  return _AviIndex(width, height, usPerFrame, offsets, sizes);
}

double? _r3(Object? n) =>
    n is num && n.isFinite ? (n * 1000).round() / 1000 : null;

class _Manifest {
  Map<String, dynamic>? header;
  final cols = <String, List<Object?>>{
    for (final k in [
      'nt',
      'sys',
      'lat',
      'v',
      'tags',
      'x',
      'y',
      'yaw',
      'x1',
      'y1',
      'yaw1',
      'temp',
      'cpu',
    ])
      k: <Object?>[],
  };

  void push(String line) {
    if (line.trim().isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    if (header == null && !decoded.containsKey('frameIndex')) {
      header = decoded;
      return;
    }
    final r = decoded['results'] is Map<String, dynamic>
        ? decoded['results'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final fi = decoded['frameIndex'];
    final i = fi is int ? fi : cols['nt']!.length;
    List<num> pose(String k) => [
      for (final v in (r[k] is List ? r[k] as List : const []))
        if (v is num) v,
    ];
    final mt2 = pose('botpose_orb_wpiblue');
    final mt1 = pose('botpose_wpiblue');
    final has2 = mt2.length >= 6 && (mt2[0] != 0 || mt2[1] != 0);
    final has1 = mt1.length >= 6 && (mt1[0] != 0 || mt1[1] != 0);
    final tsNt = r['ts_nt'];
    final tsSys = r['ts_sys'];
    final cl = r['cl'] is num ? r['cl'] as num : 0;
    final tl = r['tl'] is num ? r['tl'] as num : 0;
    final hw = r['hw'] is Map ? r['hw'] as Map : const {};
    final fid = r['Fiducial'];
    void set(String k, Object? v) {
      final col = cols[k]!;
      while (col.length <= i) {
        col.add(null);
      }
      col[i] = v;
    }

    set('nt', tsNt is num && tsNt.isFinite && tsNt > 0 ? tsNt / 1e6 : null);
    set('sys', tsSys is num && tsSys.isFinite ? (tsSys / 1000).round() : null);
    set('lat', _r3(cl + tl));
    final v = r['v'];
    set('v', v != null && v != 0 && v != false ? 1 : 0);
    set('tags', [
      if (fid is List)
        for (final f in fid)
          if (f is Map) f['fID'],
    ]);
    set('x', has2 ? _r3(mt2[0]) : null);
    set('y', has2 ? _r3(mt2[1]) : null);
    set('yaw', has2 ? _r3(mt2[5]) : null);
    set('x1', has1 ? _r3(mt1[0]) : null);
    set('y1', has1 ? _r3(mt1[1]) : null);
    set('yaw1', has1 ? _r3(mt1[5]) : null);
    set('temp', _r3(hw['temp']));
    set('cpu', _r3(hw['cpu']));
  }
}

void _readLines(_Reader r, _ZipEntry e, void Function(String) onLine) {
  void splitBytes(Uint8List bytes) {
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0a) {
        onLine(utf8.decode(bytes.sublist(start, i), allowMalformed: true));
        start = i + 1;
      }
    }
    if (start < bytes.length) {
      onLine(utf8.decode(bytes.sublist(start), allowMalformed: true));
    }
  }

  if (e.method != 0) {
    splitBytes(_memberBytes(r, e));
    return;
  }
  final rest = BytesBuilder(copy: false);
  for (var p = 0; p < e.compSize; p += _chunk) {
    final n = e.compSize - p < _chunk ? e.compSize - p : _chunk;
    final buf = r.read(e.dataOffset + p, n);
    var start = 0;
    for (var i = 0; i < buf.length; i++) {
      if (buf[i] != 0x0a) continue;
      rest.add(Uint8List.sublistView(buf, start, i));
      onLine(utf8.decode(rest.takeBytes(), allowMalformed: true));
      start = i + 1;
    }
    rest.add(Uint8List.sublistView(buf, start));
  }
  if (rest.isNotEmpty) {
    onLine(utf8.decode(rest.takeBytes(), allowMalformed: true));
  }
}

String? _mostCommon(Iterable<String> values) {
  final counts = <String, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  String? best;
  for (final e in counts.entries) {
    if (best == null || e.value > counts[best]!) best = e.key;
  }
  return best;
}

final _robotAddress = RegExp(r'\b10\.(\d{1,2})\.(\d{1,2})\.\d{1,3}\b');
final _bootHost = RegExp(
  r'^\S+\s+\d+\s+[\d:]+\s+(limelight[\w-]*)\s',
  multiLine: true,
);

int? teamFromText(String text) {
  final best = _mostCommon(
    _robotAddress
        .allMatches(text)
        .map((m) => '${int.parse(m[1]!) * 100 + int.parse(m[2]!)}'),
  );
  final n = best == null ? null : int.parse(best);
  return n != null && n > 0 ? n : null;
}

String? cameraFromName(String name) {
  final lower = name.toLowerCase();
  final m = RegExp(r'limelight-[a-z0-9]+').firstMatch(lower);
  if (m != null) return m[0];
  if (lower.contains('turret')) return 'limelight-turret';
  if (lower.contains('left')) return 'limelight-left';
  if (lower.contains('right')) return 'limelight-right';
  return null;
}

class RwndAnalysis {
  const RwndAnalysis(this.summary, this.index);
  final Map<String, dynamic> summary;
  final Map<String, dynamic> index;

  String? get camera => summary['camera'] as String?;
  int? get team => summary['team'] as int?;
  List<dynamic>? get unixMs => summary['unixMs'] as List<dynamic>?;
  List<dynamic>? get fpga => summary['fpga'] as List<dynamic>?;
}

RwndAnalysis analyzeRwnd(File file, {String? fileName}) {
  final r = _Reader(file);
  try {
    final entries = _readZip(r);
    _ZipEntry? find(bool Function(String) ok) {
      for (final e in entries) {
        if (ok(e.name)) return e;
      }
      return null;
    }

    final avi = find((n) => n.toLowerCase().endsWith('.avi'));
    final manifest = find((n) => n.endsWith('.jsonl'));
    final boot = find((n) => RegExp(r'_bootlog\.txt(\.gz)?$').hasMatch(n));
    if (avi == null) {
      throw const FormatException('no .avi video inside this .rwnd');
    }
    if (avi.method != 0) {
      throw const FormatException(
        'the video inside this .rwnd is compressed, so it cannot be streamed',
      );
    }
    final video = _indexAvi(r, avi.dataOffset, avi.compSize);
    _Manifest? man;
    if (manifest != null) {
      man = _Manifest();
      _readLines(r, manifest, man.push);
    }
    String? bootCamera;
    int? bootTeam;
    if (boot != null) {
      try {
        var bytes = _memberBytes(r, boot);
        if (boot.name.endsWith('.gz')) {
          bytes = Uint8List.fromList(gzip.decode(bytes));
        }
        final text = utf8.decode(
          bytes.length > 2 * 1024 * 1024
              ? bytes.sublist(0, 2 * 1024 * 1024)
              : bytes,
          allowMalformed: true,
        );
        bootCamera = _mostCommon(_bootHost.allMatches(text).map((m) => m[1]!));
        bootTeam = teamFromText(text);
      } on Exception {}
    }
    final camera =
        bootCamera ??
        cameraFromName(fileName ?? file.uri.pathSegments.last) ??
        cameraFromName(avi.name);

    final n = video.offsets.length;
    final cols = man?.cols;
    final header = man?.header;
    final headerFps = header?['fps'];
    final fps = headerFps is num && headerFps != 0
        ? headerFps.toDouble()
        : (video.usPerFrame != 0 ? 1e6 / video.usPerFrame : null);
    Object? firstOf(List<Object?>? a) =>
        a?.firstWhere((v) => v != null, orElse: () => null);
    Object? lastOf(List<Object?>? a) =>
        a?.lastWhere((v) => v != null, orElse: () => null);
    final ntStart = firstOf(cols?['nt']);
    final sysStart = firstOf(cols?['sys']);
    final targets = cols?['v']!.where((v) => v == 1).length;
    int? positive(Object? v) => v is num && v != 0 ? v.toInt() : null;

    final summary = <String, dynamic>{
      'version': 1,
      'camera': camera,
      'team': bootTeam,
      'members': [
        for (final e in entries)
          {'name': e.name, 'size': e.size, 'stored': e.method == 0},
      ],
      'frames': n,
      'fps': fps == null ? null : (fps * 10).round() / 10,
      'width': positive(header?['width']) ?? video.width,
      'height': positive(header?['height']) ?? video.height,
      'durationSec':
          header?['durationSeconds'] ?? (fps == null ? null : n / fps),
      'fpga': ntStart == null ? null : [ntStart, lastOf(cols?['nt'])],
      'unixMs': sysStart == null ? null : [sysStart, lastOf(cols?['sys'])],
      'targetPct': targets == null || n == 0
          ? null
          : (1000 * targets / n).round() / 10,
      'hasManifest': cols != null,
    };
    final index = <String, dynamic>{
      'version': 1,
      'frames': {'offset': video.offsets, 'size': video.sizes},
      'cols': cols,
    };
    return RwndAnalysis(summary, index);
  } finally {
    r.close();
  }
}
