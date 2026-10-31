import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/robot_log_file.dart';
import '../services/log_site_client.dart';
import '../services/robot_devices.dart';
import '../services/rwnd_file.dart';
import '../services/wpilog_reader.dart';

class RobotLogsController extends ChangeNotifier {
  RobotLogsController({
    LimelightApi? limelights,
    this._siteHttp,
    RobotConnector? connectRobot,
    Future<bool> Function(String host, int port)? isOpen,
    String? defaultFolder,
    this.autoInterval = const Duration(seconds: 30),
  }) : _limelights = limelights ?? LimelightApi(),
       _connectRobot = connectRobot ?? _sshConnect,
       _isOpen = isOpen ?? tcpOpen,
       _defaultFolder = defaultFolder ?? _homeFolder();

  static const _settingsKey = 'robot_logs_settings';
  static const _catalogKey = 'robot_logs_catalog';
  static const defaultSite = 'https://robotlog.spectrum3847.org';

  final LimelightApi _limelights;
  final http.Client? _siteHttp;
  final RobotConnector _connectRobot;
  final Future<bool> Function(String, int) _isOpen;
  final String _defaultFolder;

  String site = defaultSite;
  String uploadKey = '';
  List<int> teams = const [3847, 8515];
  late String folder = _defaultFolder;

  bool autoSync = false;
  final Duration autoInterval;
  Timer? _autoTimer;

  final Map<String, RobotLogFile> _files = {};
  RobotScan? scan;
  bool scanning = false;
  RobotLogsJob? job;

  Future<void>? _bootstrap;
  Future<void> bootstrap() => _bootstrap ??= _load().catchError((Object e) {
    _bootstrap = null;
    throw e;
  });

  List<RobotLogFile> get files => _files.values.toList()
    ..sort((a, b) => (b.recordedUnixMs ?? 0).compareTo(a.recordedUnixMs ?? 0));

  RobotLogFile? file(String rel) => _files[rel];

  bool get busy => job != null && !job!.done;

  void clearJob() {
    if (busy) return;
    job = null;
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_settingsKey);

    try {
      if (s != null) {
        final j = jsonDecode(s) as Map<String, dynamic>;
        site = j['site'] as String? ?? site;
        uploadKey = j['key'] as String? ?? '';
        teams = (j['teams'] as List?)?.cast<int>() ?? teams;
        folder = j['folder'] as String? ?? folder;
        autoSync = j['auto'] as bool? ?? false;
      }
    } on Object {}
    final c = prefs.getString(_catalogKey);
    try {
      if (c != null) {
        for (final e in (jsonDecode(c) as List).cast<Map<String, dynamic>>()) {
          final f = RobotLogFile.fromJson(e);
          _files[f.rel] = f;
        }
      }
    } on Object {
      _files.clear();
    }
    await refreshFolder();
    _armAuto();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _settingsKey,
      jsonEncode({
        'site': site,
        'key': uploadKey,
        'teams': teams,
        'folder': folder,
        'auto': autoSync,
      }),
    );
    await prefs.setString(
      _catalogKey,
      jsonEncode([for (final f in _files.values) f.toJson()]),
    );
  }

  Future<void> flushPendingSaves() async {
    if (busy) await _save();
  }

  String localPath(String rel) =>
      '$folder${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}';

  Future<void> refreshFolder() async {
    final dir = Directory(folder);
    final found = <String, int>{};
    if (await dir.exists()) {
      final root = dir.absolute.path;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = e.absolute.path
            .substring(root.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        if (rel.contains('/.parts/')) continue;
        final lower = rel.toLowerCase();
        if (lower.endsWith('.wpilog') || lower.endsWith('.rwnd')) {
          found[rel] = await e.length();
        }
      }
    }
    _files.removeWhere((rel, f) => found[rel] != f.size);
    for (final MapEntry(key: rel, value: size) in found.entries) {
      final old = _files[rel];
      if (old != null && old.modifiedMs != null) continue;
      final team = int.tryParse(rel.split('/').first);
      try {
        final fresh = await _read(rel, size, team);
        if (old != null) {
          fresh
            ..name = old.name
            ..nameEdited = old.nameEdited
            ..team = old.teamEdited ? old.team : fresh.team
            ..teamEdited = old.teamEdited
            ..uploaded = old.uploaded;
        }
        _files[rel] = fresh;
      } on Object {}
    }
    proposeNames(_files.values.toList());
    await _save();
    notifyListeners();
  }

  Future<RobotLogFile> _read(String rel, int size, int? sourceTeam) async {
    final path = localPath(rel);
    final modifiedMs = (await File(path).lastModified()).millisecondsSinceEpoch;
    if (rel.toLowerCase().endsWith('.wpilog')) {
      final facts = WpiLogFacts.fromJson(await compute(_readWpilogFacts, path));
      return RobotLogFile(
        rel: rel,
        kind: RobotLogKind.wpilog,
        size: size,
        sourceTeam: sourceTeam,
        wpilog: facts,
        team: matchFor(
          facts,
          rel.split('/').last,
          fallbackTeam: sourceTeam,
        ).team,
        modifiedMs: modifiedMs,
      );
    }
    final facts = RwndFacts.fromJson(await compute(_readRwndFacts, path));
    return RobotLogFile(
      rel: rel,
      kind: RobotLogKind.rwnd,
      size: size,
      sourceTeam: sourceTeam,
      rwnd: facts,
      team: facts.team ?? sourceTeam,
      modifiedMs: modifiedMs,
    );
  }

  Future<String> saveSettings({
    required String site,
    required String uploadKey,
    required List<int> teams,
    required String folder,
  }) async {
    if (busy || scanning) {
      throw StateError('Wait for the current job to finish');
    }
    this.site = site.trim().replaceFirst(RegExp(r'/+$'), '');
    this.uploadKey = uploadKey.trim();
    this.teams = teams.where((t) => t > 0 && t < 100000).toList();
    final newFolder = folder.trim();
    final moved = newFolder.isNotEmpty && newFolder != this.folder;
    if (moved) {
      this.folder = newFolder;
      _files.clear();
    }
    await _save();
    notifyListeners();
    if (moved) await refreshFolder();
    try {
      await _siteClient().checkKey();
      return 'Key accepted by the log site.';
    } on LogSiteException catch (e) {
      return e.status == 401
          ? 'The log site did not accept this key.'
          : 'Log site error: $e';
    } on Object catch (e) {
      return 'Log site not reachable: $e';
    }
  }

  LogSiteClient _siteClient() =>
      LogSiteClient(site: site, key: uploadKey, client: _siteHttp);

  Future<void> scanDevices() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    final robots = <ScannedRobot>[];
    final cameras = <ScannedLimelight>[];
    final errors = <String>[];
    try {
      for (final team in teams) {
        for (final host in robotHosts(team)) {
          if (!await _isOpen(host, 22)) continue;
          try {
            final conn = await _connectRobot(host, 22);
            try {
              robots.add(
                ScannedRobot(
                  team: team,
                  host: host,
                  username: conn.username,
                  files: await conn.listLogs(),
                ),
              );
            } finally {
              conn.close();
            }
          } on Object catch (e) {
            errors.add('Robot $team at $host: $e');
          }
          break;
        }
      }

      final cameraTeams = robots.isEmpty
          ? teams
          : robots.map((r) => r.team).toSet().toList();
      final tried = <String>{};
      for (final team in cameraTeams) {
        final hosts = limelightHosts(team).where(tried.add).toList();
        final found = await Future.wait(hosts.map(_limelights.probe));
        for (final ll in found.whereType<Limelight>()) {
          if (cameras.any((c) => c.limelight.name == ll.name)) continue;
          cameras.add(ScannedLimelight(team: team, limelight: ll));
        }
      }
    } finally {
      scan = RobotScan(
        at: DateTime.now(),
        robots: robots,
        limelights: cameras,
        errors: errors,
      );
      scanning = false;
      notifyListeners();
    }
  }

  String robotRel(int team, RobotFile f) =>
      '$team/robot/${safeLogName(f.name)}';
  String recordingRel(ScannedLimelight c, LimelightRecording r) =>
      '${c.team}/${safeLogName(c.limelight.name)}/${safeLogName(r.base)}.rwnd';

  bool isPulled(String rel, {int? size}) {
    final f = _files[rel];
    return f != null && (size == null || f.size == size);
  }

  List<RemoteItem> get newRemoteItems {
    final s = scan;
    if (s == null) return const [];
    return [
      for (final r in s.robots)
        for (final f in r.files)
          if (!isPulled(robotRel(r.team, f), size: f.size)) RobotLogItem(r, f),
      for (final c in s.limelights)
        for (final rec in c.limelight.recordings)
          if (!isPulled(recordingRel(c, rec))) RecordingItem(c, rec),
    ];
  }

  Future<void> syncAll({bool auto = false}) async {
    if (busy || scanning || (auto && _autoHolds > 0)) return;
    if (auto && !await _anyRobotAnswers()) {
      if (scan?.robots.isNotEmpty ?? true) {
        scan = RobotScan(
          at: DateTime.now(),
          robots: const [],
          limelights: const [],
          errors: const [],
        );
        notifyListeners();
      }
      return;
    }
    if (!auto) _failed.clear();
    await scanDevices();
    final fresh = newRemoteItems;
    if (fresh.isNotEmpty) await pull(fresh);
    final copyErrors = [...?job?.errors];
    final unsent = unsentRels.where((r) => !_failed.contains(r)).toList();
    if (uploadKey.isNotEmpty && unsent.isNotEmpty) {
      await upload(unsent);

      if (fresh.isNotEmpty) job?.errors.insertAll(0, copyErrors);
    }
  }

  final Set<String> _failed = {};
  int _autoHolds = 0;

  void holdAuto() => _autoHolds++;
  void releaseAuto() => _autoHolds = _autoHolds > 0 ? _autoHolds - 1 : 0;

  Future<bool> _anyRobotAnswers() async {
    final checks = [
      for (final t in teams)
        for (final h in robotHosts(t)) _isOpen(h, 22),
    ];
    return (await Future.wait(checks)).any((ok) => ok);
  }

  Future<void> setAutoSync(bool on) async {
    autoSync = on;
    _armAuto();
    await _save();
    notifyListeners();
    if (on) await syncAll();
  }

  void _armAuto() {
    _autoTimer?.cancel();
    _autoTimer = autoSync
        ? Timer.periodic(autoInterval, (_) => unawaited(syncAll(auto: true)))
        : null;
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  List<LogGroup> get groups {
    final byKey = <String, LogGroup>{};
    LogGroup group(String key, String title) =>
        byKey.putIfAbsent(key, () => LogGroup(title));
    for (final f in files) {
      final log = f.kind == RobotLogKind.wpilog
          ? f
          : (f.pairedWith == null ? null : _files[f.pairedWith!]);
      if (log == null) {
        group('file:${f.rel}', f.rwnd?.camera ?? f.original).files.add(f);
        continue;
      }
      final m = matchFor(log.wpilog!, log.name, fallbackTeam: log.sourceTeam);
      final title = m.label == null
          ? log.name
          : (m.team == null ? m.label! : '${m.team} ${m.label}');
      group('log:${log.rel}', title).files.add(f);
    }
    final out = byKey.values.toList()
      ..sort(
        (a, b) => (b.recordedUnixMs ?? 0).compareTo(a.recordedUnixMs ?? 0),
      );
    return out;
  }

  Future<void> saveRewindBuffer(ScannedLimelight c, {int seconds = 165}) =>
      _limelights.flush(c.limelight, seconds: seconds);

  Future<void> _runJob<T>(
    String title,
    List<T> items,
    String Function(T) label,
    Future<void> Function(T, void Function(double)) work,
  ) async {
    if (busy) return;
    final j = RobotLogsJob(title: title, total: items.length);
    job = j;
    notifyListeners();
    var shown = -1;
    try {
      for (final item in items) {
        final name = label(item);
        j
          ..current = name
          ..progress = 0;
        notifyListeners();
        try {
          await work(item, (p) {
            j.progress = p;
            final pct = (p * 100).floor();
            if (pct != shown) {
              shown = pct;
              notifyListeners();
            }
          });
        } on Object catch (e) {
          j.errors.add('$name: $e');
        }
        j.index++;
      }
    } finally {
      j
        ..done = true
        ..current = '';
      proposeNames(_files.values.toList());
      await _save();
      notifyListeners();
    }
  }

  Future<void> pull(List<RemoteItem> items) => _runJob(
    'Copy',
    items,
    (i) => i.label,
    (i, progress) => switch (i) {
      RobotLogItem() => _pullRobotFile(i, progress),
      RecordingItem() => _pullRecording(i, progress),
    },
  );

  Future<void> _pullRobotFile(
    RobotLogItem item,
    void Function(double) progress,
  ) async {
    final rel = robotRel(item.robot.team, item.file);
    final conn = await _connectRobot(
      item.robot.host,
      22,
      username: item.robot.username,
    );
    try {
      await conn.download(
        item.file.path,
        File(localPath(rel)),
        size: item.file.size,
        onProgress: progress,
      );
    } finally {
      conn.close();
    }
    _files[rel] = await _read(rel, item.file.size, item.robot.team);
  }

  Future<void> _pullRecording(
    RecordingItem item,
    void Function(double) progress,
  ) async {
    final rel = recordingRel(item.camera, item.recording);
    final out = File(localPath(rel));
    final parts = Directory(
      '${out.parent.path}${Platform.pathSeparator}.parts${Platform.pathSeparator}${safeLogName(item.recording.base)}',
    );
    try {
      final files = await _limelights.download(
        item.camera.limelight,
        item.recording,
        parts,
        onProgress: (p) => progress(p * 0.9),
      );
      await compute(_zipParts, [out.path, for (final f in files) f.path]);
    } finally {
      if (await parts.exists()) await parts.delete(recursive: true);
    }
    progress(1);
    _files[rel] = await _read(rel, await out.length(), item.camera.team);
  }

  Future<void> upload(List<String> rels) {
    final items = rels.where(_files.containsKey).toList()
      ..sort((a, b) => _files[a]!.kind.index.compareTo(_files[b]!.kind.index));
    final names = {for (final rel in items) rel: _files[rel]!.name};
    return _runJob('Send', items, (rel) => names[rel]!, _uploadOne);
  }

  List<String> get unsentRels => [
    for (final f in files)
      if (!f.isSent) f.rel,
  ];

  Future<void> _uploadOne(String rel, void Function(double) progress) async {
    _failed.add(rel);
    await _send(rel, progress);
    _failed.remove(rel);
  }

  Future<void> _send(String rel, void Function(double) progress) async {
    final f = _files[rel];
    if (f == null) throw StateError('no longer in the logs folder');
    if (uploadKey.isEmpty) {
      throw StateError('set the upload key in Settings first');
    }
    final override = f.teamEdited ? f.team : null;
    final Map<String, dynamic> filing;
    Map<String, dynamic>? index;
    if (f.kind == RobotLogKind.wpilog) {
      final facts = f.wpilog!;
      final m = matchFor(
        facts,
        f.name,
        team: override,
        fallbackTeam: f.sourceTeam ?? f.team,
      );

      filing = {
        'team': m.team,
        'match': m.toJson(),
        'unixStartMs': facts.unixStartMs,
        'unixEndMs': facts.unixEndMs,
        'fpgaStart': facts.firstTs,
        'fpgaEnd': facts.lastTs,
        'phases': [for (final p in facts.phases) p.toJson()],
      };
    } else {
      final a = await compute(_analyzeRwnd, [localPath(rel), f.name]);
      final summary = a['summary'] as Map<String, dynamic>;
      final unix = summary['unixMs'] as List?;
      final fpga = summary['fpga'] as List?;
      final team = override ?? summary['team'] as int? ?? f.sourceTeam;
      index = a['index'] as Map<String, dynamic>;
      filing = {
        'summary': summary,
        'camera': summary['camera'],
        'team': team,
        'unixStartMs': unix?.first,
        'unixEndMs': unix?.last,
        'fpgaStart': fpga?.first,
        'fpgaEnd': fpga?.last,
      };
    }
    final res = await _siteClient().upload(
      File(localPath(rel)),
      name: f.name,
      kind: f.kind.name,
      filing: filing,
      index: index,
      onProgress: progress,
    );
    f.uploaded = RobotLogUpload(
      at: DateTime.now(),
      name: f.name,
      matchId: res.matchId,
      duplicate: res.duplicate,
    );
  }

  Uri? matchUrl(RobotLogFile f) {
    final id = f.uploaded?.matchId;
    return id == null ? null : Uri.tryParse('$site/#/match/$id');
  }

  Future<bool> rename(String rel, String name) async {
    final f = _files[rel];
    if (f == null) return false;
    final clean = safeLogName(
      name.trim().replaceFirst(
        RegExp(r'\.(wpilog|rwnd)$', caseSensitive: false),
        '',
      ),
    );
    if (clean.isEmpty || clean == '_') return false;
    f
      ..name = '$clean${f.kind.extension}'
      ..nameEdited = true;
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> resetName(String rel) async {
    final f = _files[rel];
    if (f == null) return;
    f.nameEdited = false;
    proposeNames(_files.values.toList(), reset: f);
    await _save();
    notifyListeners();
  }

  Future<void> setTeam(String rel, int? team) async {
    final f = _files[rel];
    if (f == null) return;
    if (team == null) {
      f
        ..teamEdited = false
        ..team = f.wpilog != null
            ? matchFor(f.wpilog!, f.original, fallbackTeam: f.sourceTeam).team
            : (f.rwnd?.team ?? f.sourceTeam);
    } else {
      f
        ..team = team
        ..teamEdited = true;
    }
    await _save();
    notifyListeners();
  }
}

typedef RobotConnector = Future<RobotShell> Function(
  String host,
  int port, {
  String? username,
});

abstract interface class RobotShell {
  String get username;
  Future<List<RobotFile>> listLogs();
  Future<void> download(
    String remote,
    File local, {
    required int size,
    void Function(double)? onProgress,
  });
  void close();
}

class _SshShell implements RobotShell {
  _SshShell(this._conn);
  final RobotConnection _conn;
  @override
  String get username => _conn.login.username;
  @override
  Future<List<RobotFile>> listLogs() => _conn.listLogs();
  @override
  Future<void> download(
    String remote,
    File local, {
    required int size,
    void Function(double)? onProgress,
  }) => _conn.download(remote, local, size: size, onProgress: onProgress);
  @override
  void close() => _conn.close();
}

Future<RobotShell> _sshConnect(
  String host,
  int port, {
  String? username,
}) async => _SshShell(
  await RobotConnection.open(
    host,
    port: port,
    logins: username == null
        ? robotLogins
        : robotLogins.where((l) => l.username == username).toList(),
  ),
);

String _homeFolder() {
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  return '$home${Platform.pathSeparator}SpectrumLogs';
}

Map<String, dynamic> _readWpilogFacts(String path) =>
    readWpiLogFacts(File(path).readAsBytesSync()).toJson();

Map<String, dynamic> _readRwndFacts(String path) {
  final s = analyzeRwnd(File(path)).summary;
  final unix = s['unixMs'] as List?;
  final fpga = s['fpga'] as List?;
  return RwndFacts(
    camera: s['camera'] as String?,
    team: s['team'] as int?,
    unixStartMs: unix?.first as int?,
    unixEndMs: unix?.last as int?,
    frames: s['frames'] as int,
    durationSec: (s['durationSec'] as num?)?.toDouble(),
    fpgaStart: (fpga?.first as num?)?.toDouble(),
    fpgaEnd: (fpga?.last as num?)?.toDouble(),
  ).toJson();
}

Map<String, dynamic> _analyzeRwnd(List<String> args) {
  final a = analyzeRwnd(File(args[0]), fileName: args[1]);
  return {'summary': a.summary, 'index': a.index};
}

void _zipParts(List<String> args) {
  final out = File(args.first);
  out.parent.createSync(recursive: true);
  writeStoredZip(out, [
    for (final p in args.skip(1)) (File(p).uri.pathSegments.last, File(p)),
  ]);
}

class ScannedRobot {
  const ScannedRobot({
    required this.team,
    required this.host,
    required this.username,
    required this.files,
  });
  final int team;
  final String host;
  final String username;
  final List<RobotFile> files;
}

class ScannedLimelight {
  const ScannedLimelight({required this.team, required this.limelight});
  final int team;
  final Limelight limelight;
}

class RobotScan {
  const RobotScan({
    required this.at,
    required this.robots,
    required this.limelights,
    required this.errors,
  });
  final DateTime at;
  final List<ScannedRobot> robots;
  final List<ScannedLimelight> limelights;
  final List<String> errors;
}

sealed class RemoteItem {
  const RemoteItem();
  String get label;
}

class RobotLogItem extends RemoteItem {
  const RobotLogItem(this.robot, this.file);
  final ScannedRobot robot;
  final RobotFile file;
  @override
  String get label => file.name;
}

class RecordingItem extends RemoteItem {
  const RecordingItem(this.camera, this.recording);
  final ScannedLimelight camera;
  final LimelightRecording recording;
  @override
  String get label => '${camera.limelight.name} ${recording.video}';
}

class LogGroup {
  LogGroup(this.title);
  final String title;
  final List<RobotLogFile> files = [];

  int? get recordedUnixMs => files
      .map((f) => f.recordedUnixMs)
      .whereType<int>()
      .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
  bool get sent => files.every((f) => f.isSent);
  int get logCount => files.where((f) => f.kind == RobotLogKind.wpilog).length;
  int get rewindCount => files.length - logCount;
}

class RobotLogsJob {
  RobotLogsJob({required this.title, required this.total});
  final String title;
  final int total;
  int index = 0;
  String current = '';
  double progress = 0;
  bool done = false;
  final List<String> errors = [];
}
