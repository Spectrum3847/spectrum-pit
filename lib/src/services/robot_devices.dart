import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

String teamNet(int team) => '10.${team ~/ 100}.${team % 100}';

List<String> robotHosts(int team) => [
  '${teamNet(team)}.2',
  'roborio-$team-frc.local',
  'systemcore-$team.local',
  '172.22.11.2',
];

const defaultLimelightNames = [
  'limelight-left',
  'limelight-right',
  'limelight-turret',
  'limelight-back',
  'limelight-front',
  'limelight',
];

List<String> limelightHosts(int team) => [
  for (final n in defaultLimelightNames) '$n.local',
  for (var i = 11; i <= 19; i++) '${teamNet(team)}.$i',
];

typedef RobotLogin = ({String username, String password});

const robotLogins = <RobotLogin>[
  (username: 'lvuser', password: ''),
  (username: 'admin', password: ''),
  (username: 'systemcore', password: 'systemcore'),
  (username: 'root', password: ''),
];

const robotLogDirs = [
  '/home/systemcore/logs',
  '/U/logs',
  '/home/lvuser/logs',
  '/media/sda1/logs',
  '/home/systemcore/lvuser/logs',
  '/home/admin/logs',
];

class RobotFile {
  const RobotFile({
    required this.path,
    required this.size,
    required this.modified,
  });
  final String path;
  final int size;
  final DateTime modified;

  String get name => path.split('/').last;
}

class LimelightRecording {
  const LimelightRecording({
    required this.video,
    required this.manifest,
    required this.bootlog,
    required this.size,
  });
  final String video;
  final String? manifest;
  final String? bootlog;
  final int? size;

  String get base =>
      video.replaceFirst(RegExp(r'\.avi$', caseSensitive: false), '');

  List<String> get parts => [video, ?manifest, ?bootlog];
}

class Limelight {
  const Limelight({
    required this.host,
    required this.port,
    required this.name,
    required this.recordings,
  });
  final String host;
  final int port;
  final String name;
  final List<LimelightRecording> recordings;
}

Future<bool> tcpOpen(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 1200),
}) async {
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    s.destroy();
    return true;
  } on Object {
    return false;
  }
}

class RobotConnection {
  RobotConnection._(this._client, this.login);

  @visibleForTesting
  RobotConnection.forTesting(SSHClient client, RobotLogin login)
    : this._(client, login);
  final SSHClient _client;
  final RobotLogin login;

  static Future<RobotConnection> open(
    String host, {
    int port = 22,
    List<RobotLogin> logins = robotLogins,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    Object? last;
    for (final login in logins) {
      SSHClient? client;
      try {
        final socket = await SSHSocket.connect(host, port, timeout: timeout);
        client = SSHClient(
          socket,
          username: login.username,
          onPasswordRequest: () => login.password,

          onUserInfoRequest: (req) => [
            for (final _ in req.prompts) login.password,
          ],
          handshakeTimeout: timeout,
          authTimeout: timeout,
          algorithms: _fastCiphers,
        );
        await client.authenticated;
        return RobotConnection._(client, login);
      } on Object catch (e) {
        client?.close();
        last = e;
      }
    }
    final users = logins.map((l) => l.username).join(', ');
    throw RobotDeviceException('could not log in to $host ($users): $last');
  }

  Future<String> _run(String cmd, Duration timeout) async {
    final session = await _client.execute(cmd);
    final out = BytesBuilder(copy: false);
    final sub = session.stdout.listen(out.add);
    session.stderr.drain<void>();
    try {
      await session.done.timeout(
        timeout,
        onTimeout: () {
          session.close();
          throw RobotDeviceException(
            'timed out: ${cmd.substring(0, cmd.length < 60 ? cmd.length : 60)}',
          );
        },
      );
    } finally {
      await sub.cancel();
    }
    return utf8.decode(out.takeBytes(), allowMalformed: true);
  }

  Future<List<RobotFile>> listLogs({List<String> dirs = robotLogDirs}) async {
    final loop =
        'for d in ${dirs.map(shellQuote).join(' ')}; do for f in "\$d"/*.wpilog; do '
        '[ -f "\$f" ] && echo "\$(stat -c \'%s %Y\' "\$f" 2>/dev/null) \$f"; done; done; true';
    var out = await _run(
      'sh -c ${shellQuote(loop)}',
      const Duration(seconds: 30),
    );
    if (out.trim().isEmpty) {
      const wide =
          "find /home /media /U /mnt /var/log -maxdepth 5 -name '*.wpilog' 2>/dev/null | head -500 | "
          'while read f; do echo "\$(stat -c \'%s %Y\' "\$f" 2>/dev/null) \$f"; done; true';
      out = await _run(
        'sh -c ${shellQuote(wide)}',
        const Duration(seconds: 60),
      );
    }
    return parseLogListing(out);
  }

  Future<void> download(
    String remote,
    File local, {
    required int size,
    void Function(double)? onProgress,
  }) async {
    await local.parent.create(recursive: true);
    final tmp = File('${local.path}.part');
    final sink = tmp.openWrite();
    var got = 0;
    final err = BytesBuilder(copy: false);
    int? exit;
    try {
      final session = await _client.execute('cat ${shellQuote(remote)}');
      final errSub = session.stderr.listen(err.add);
      try {
        await for (final chunk in session.stdout.timeout(_idle)) {
          sink.add(chunk);
          got += chunk.length;
          if (size > 0) onProgress?.call(got / size);
        }
        await session.done.timeout(_idle);
      } finally {
        session.close();
        await errSub.cancel();
      }
      exit = session.exitCode;
    } on Object {
      await sink.close();
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    await sink.close();
    if ((exit != null && exit != 0) || got != size) {
      await tmp.delete();
      final stderr = utf8.decode(err.takeBytes(), allowMalformed: true).trim();
      throw RobotDeviceException(
        exit != null && exit != 0
            ? 'could not read $remote: ${stderr.isEmpty ? 'exit $exit' : stderr.split('\n').last}'
            : 'got $got of $size bytes for $remote; the robot may still be writing it',
      );
    }
    await tmp.rename(local.path);
  }

  void close() => _client.close();
}

const _idle = Duration(seconds: 30);

String? _name(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

const _fastCiphers = SSHAlgorithms(
  cipher: [
    SSHCipherType.chacha20poly1305,
    SSHCipherType.aes128ctr,
    SSHCipherType.aes256ctr,
    SSHCipherType.aes128gcm,
    SSHCipherType.aes256gcm,
  ],
);

String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

final _listingLine = RegExp(r'^(\d+) (\d+) (.+\.wpilog)$');

List<RobotFile> parseLogListing(String out) {
  final seen = <String>{};
  final files = <RobotFile>[];
  for (final line in const LineSplitter().convert(out)) {
    final m = _listingLine.firstMatch(line.trim());
    if (m == null || !seen.add(m[3]!)) continue;
    files.add(
      RobotFile(
        path: m[3]!,
        size: int.parse(m[1]!),
        modified: DateTime.fromMillisecondsSinceEpoch(int.parse(m[2]!) * 1000),
      ),
    );
  }
  return files..sort((a, b) => b.modified.compareTo(a.modified));
}

class RobotDeviceException implements Exception {
  const RobotDeviceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LimelightApi {
  LimelightApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Uri _uri(String host, int port, String path, [Map<String, String>? q]) => Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: path,
    queryParameters: q,
  );

  Future<Object?> _json(Uri uri, Duration timeout) async {
    final res = await _client.get(uri).timeout(timeout);
    if (res.statusCode != 200) {
      throw RobotDeviceException('${res.statusCode} from $uri');
    }
    return jsonDecode(res.body);
  }

  Future<Limelight?> probe(String host, {int port = 5807}) async {
    final Object? status;
    try {
      status = await _json(
        _uri(host, port, '/status'),
        const Duration(milliseconds: 1500),
      );
    } on Object {
      return null;
    }
    var recordings = <LimelightRecording>[];
    try {
      final list = await _json(
        _uri(host, port, '/recording-list'),
        const Duration(seconds: 4),
      );
      final raw = list is List
          ? list
          : (list is Map && list['recordings'] is List
                ? list['recordings'] as List
                : const []);
      recordings = [
        for (final r in raw)
          if (r is Map && _name(r['video']) != null)
            LimelightRecording(
              video: r['video'] as String,
              manifest: _name(r['manifest']),
              bootlog: _name(r['bootlog']),
              size: (r['size'] as num?)?.toInt(),
            ),
      ];
    } on Object {}
    final s = status is Map ? status : const {};
    final name = (s['name'] ?? s['hostname']) as String?;
    return Limelight(
      host: host,
      port: port,
      name: name ?? host.replaceFirst(RegExp(r'\.local$'), ''),
      recordings: recordings,
    );
  }

  Future<List<File>> download(
    Limelight ll,
    LimelightRecording rec,
    Directory dir, {
    void Function(double)? onProgress,
  }) async {
    await dir.create(recursive: true);
    final out = <File>[];
    var done = 0;
    for (final name in rec.parts) {
      final req = http.Request(
        'GET',
        Uri(
          scheme: 'http',
          host: ll.host,
          port: ll.port,
          pathSegments: ['recording', name],
        ),
      );
      final res = await _client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw RobotDeviceException(
          '${res.statusCode} downloading $name from ${ll.host}',
        );
      }

      final local = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
      final file = File('${dir.path}${Platform.pathSeparator}$local');
      final tmp = File('${file.path}.part');
      final sink = tmp.openWrite();
      try {
        await for (final chunk in res.stream.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          done += chunk.length;
          final total = rec.size;
          if (total != null && total > 0) {
            onProgress?.call((done / total).clamp(0, 1));
          }
        }
      } finally {
        await sink.close();
      }
      await tmp.rename(file.path);
      out.add(file);
    }
    return out;
  }

  Future<void> flush(Limelight ll, {int seconds = 165}) async {
    final res = await _client
        .post(
          _uri(ll.host, ll.port, '/recording-flush', {'duration': '$seconds'}),
        )
        .timeout(const Duration(seconds: 15));
    Object? body;
    try {
      body = jsonDecode(res.body);
    } on FormatException {
      body = null;
    }
    final failed = body is Map && body['success'] == false;
    if (res.statusCode != 200 || failed) {
      final msg = body is Map ? body['message'] : null;
      throw RobotDeviceException(
        msg is String ? msg : 'flush failed (${res.statusCode})',
      );
    }
  }
}
