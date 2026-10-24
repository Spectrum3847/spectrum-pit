import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/robot_log_file.dart';
import 'package:spectrumpit/src/services/robot_devices.dart';
import 'package:spectrumpit/src/state/robot_logs_controller.dart';

import 'support/fake_log_site.dart';
import 'support/fake_robot_devices.dart';
import 'support/robot_log_fixtures.dart';

void main() {
  late Directory dir;
  late Map<String, File> parts;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('robot_logs_test');
    final partsDir = Directory('${dir.path}/fixture')..createSync();
    parts = {
      for (final f in writeRecordingParts(partsDir)) f.uri.pathSegments.last: f,
    };
  });
  tearDown(() => dir.deleteSync(recursive: true));

  RobotLogsController controller(FakeRobot robot, FakeLogSite site) =>
      RobotLogsController(
        limelights: LimelightApi(client: fakeLimelight(parts)),
        siteHttp: site.client,
        connectRobot: (host, port, {username}) async {
          robot.opened++;
          return robot;
        },
        isOpen: (host, port) async => host == '10.38.47.2',
        defaultFolder: '${dir.path}/logs',
      );

  test('scans, copies, names, sends, and remembers', () async {
    final robot = FakeRobot({
      '/U/logs/FRC_20261016_101256_TXMAN1_Q3.wpilog': matchLog(),
    });
    final site = FakeLogSite(partSize: 1 << 20);
    final c = controller(robot, site);
    await c.bootstrap();
    expect(c.files, isEmpty);

    await c.scanDevices();
    final scan = c.scan!;
    expect(scan.robots.single.team, 3847);
    expect(
      scan.robots.single.files.single.name,
      'FRC_20261016_101256_TXMAN1_Q3.wpilog',
    );
    expect(scan.limelights.single.limelight.name, 'limelight-left');
    expect(c.newRemoteItems, hasLength(2));

    await c.pull(c.newRemoteItems);
    expect(c.job!.errors, isEmpty);
    expect(c.newRemoteItems, isEmpty);
    expect(
      File('${dir.path}/logs/3847/limelight-left/rec1.rwnd').existsSync(),
      isTrue,
    );
    expect(
      Directory('${dir.path}/logs/3847/limelight-left/.parts/rec1')
          .existsSync(),
      isFalse,
    );

    final log = c.files.firstWhere((f) => f.kind == RobotLogKind.wpilog);
    final rewind = c.files.firstWhere((f) => f.kind == RobotLogKind.rwnd);
    expect(log.name, '3847_TXMAN1_Q3.wpilog');
    expect(rewind.name, '3847_TXMAN1_Q3_limelight-left.rwnd');
    expect(rewind.pairedWith, log.rel);
    expect(rewind.rwnd!.fpgaStart, 100);
    expect(rewind.modifiedMs, isNotNull);

    c.uploadKey = 'key';
    await c.upload(c.unsentRels);
    expect(c.job!.errors, isEmpty);

    expect(site.calls.first, 'POST uploads');
    expect(site.completed.keys, [
      '3847_TXMAN1_Q3.wpilog',
      '3847_TXMAN1_Q3_limelight-left.rwnd',
    ]);
    final logFiling = site.completed['3847_TXMAN1_Q3.wpilog']!;
    expect(logFiling.containsKey('summary'), isFalse);
    expect((logFiling['match'] as Map)['key'], '3847-txman1-q3-r1');
    expect(logFiling['unixStartMs'], 1760629990000);
    final phases = logFiling['phases'] as List;
    expect(phases, hasLength(1));
    expect(phases.single, {'phase': 'teleop', 'start': 10, 'end': 160});
    final rwFiling = site.completed['3847_TXMAN1_Q3_limelight-left.rwnd']!;
    expect(rwFiling['camera'], 'limelight-left');
    expect(rwFiling['team'], 3847);
    expect(rwFiling['unixStartMs'], 1760630000000);
    expect(site.indexes, hasLength(1));
    expect(c.unsentRels, isEmpty);
    expect(
      c.matchUrl(log).toString(),
      '${RobotLogsController.defaultSite}/#/match/match-f0',
    );

    final again = controller(robot, site);
    await again.bootstrap();
    expect(again.files, hasLength(2));
    expect(again.unsentRels, isEmpty);
    expect(again.uploadKey, 'key');
  });

  test(
    'a rename is kept and sends the file again under the new name',
    () async {
      final robot = FakeRobot({'/U/logs/a.wpilog': matchLog(matchNumber: 7)});
      final site = FakeLogSite(partSize: 1 << 20);
      final c = controller(robot, site)..uploadKey = 'key';
      await c.bootstrap();
      await c.scanDevices();
      await c.pull([c.newRemoteItems.firstWhere((i) => i is RobotLogItem)]);
      final rel = c.files.single.rel;
      await c.upload([rel]);
      expect(c.unsentRels, isEmpty);

      expect(await c.rename(rel, '  8515_TXMAN1_E1.wpilog '), isTrue);
      await c.setTeam(rel, 8515);
      expect(c.file(rel)!.name, '8515_TXMAN1_E1.wpilog');
      expect(c.unsentRels, [rel]);
      await c.upload([rel]);
      final filing = site.completed['8515_TXMAN1_E1.wpilog']!;

      expect((filing['match'] as Map)['key'], '8515-txman1-q7-r1');
      expect(filing['team'], 8515);

      expect(await c.rename(rel, '   '), isFalse);
      await c.resetName(rel);
      expect(c.file(rel)!.name, '3847_TXMAN1_Q7.wpilog');
    },
  );

  test('sending without a key fails each file with a clear error', () async {
    final robot = FakeRobot({'/U/logs/a.wpilog': matchLog()});
    final c = controller(robot, FakeLogSite());
    await c.bootstrap();
    await c.scanDevices();
    await c.pull(c.newRemoteItems);
    await c.upload(c.unsentRels);
    expect(c.job!.errors, hasLength(2));
    expect(c.job!.errors.first, contains('upload key'));
  });

  test('a robot that will not log in is reported, not thrown', () async {
    final c = RobotLogsController(
      limelights: LimelightApi(
        client: MockClient((_) async => throw const SocketException('x')),
      ),
      connectRobot: (host, port, {username}) async =>
          throw const RobotDeviceException('could not log in'),
      isOpen: (host, port) async => host == '10.38.47.2',
      defaultFolder: '${dir.path}/logs',
    );
    await c.bootstrap();
    await c.scanDevices();
    expect(c.scan!.robots, isEmpty);
    expect(c.scan!.errors.single, contains('could not log in'));
  });

  test('a failed recording download leaves no parts behind', () async {
    final good = fakeLimelight(parts);
    final c = RobotLogsController(
      limelights: LimelightApi(
        client: MockClient((req) async {
          if (req.url.path.endsWith('_manifest.jsonl')) {
            return http.Response('gone', 500);
          }
          return good.get(req.url);
        }),
      ),
      connectRobot: (host, port, {username}) async => FakeRobot({}),
      isOpen: (host, port) async => false,
      defaultFolder: '${dir.path}/logs',
    );
    await c.bootstrap();
    await c.scanDevices();
    expect(c.newRemoteItems, hasLength(1));
    await c.pull(c.newRemoteItems);
    expect(c.job!.done, isTrue);
    expect(c.job!.errors.single, contains('500'));
    expect(c.files, isEmpty);
    final cam = Directory('${dir.path}/logs/3847/limelight-left');
    expect(
      cam.listSync(recursive: true).whereType<File>().map((f) => f.path),
      isEmpty,
    );
  });

  test('a flush mid-send keeps the files already sent', () async {
    final robot = FakeRobot({'/U/logs/a.wpilog': matchLog()});
    final site = FakeLogSite(partSize: 1 << 20);
    final c = controller(robot, site)..uploadKey = 'key';
    await c.bootstrap();
    await c.scanDevices();
    await c.pull(c.newRemoteItems);
    final reached = Completer<void>();
    final release = Completer<void>();
    site.beforeUpload = (name) async {
      if (!name.endsWith('.rwnd')) return;
      reached.complete();
      await release.future;
    };
    final send = c.upload(c.unsentRels);
    await reached.future;
    await c.flushPendingSaves();

    final again = controller(robot, site);
    await again.bootstrap();
    expect(again.unsentRels, hasLength(1));
    expect(again.file(again.unsentRels.single)!.kind, RobotLogKind.rwnd);

    release.complete();
    await send;
  });

  test('settings cannot change while a job runs', () async {
    final robot = FakeRobot({'/U/logs/a.wpilog': matchLog()});
    final c = controller(robot, FakeLogSite());
    await c.bootstrap();
    await c.scanDevices();
    final job = c.pull(c.newRemoteItems);
    expect(c.busy, isTrue);
    await expectLater(
      c.saveSettings(site: 'x', uploadKey: '', teams: [1], folder: 'y'),
      throwsStateError,
    );
    await job;
    expect(c.busy, isFalse);
  });

  test('unreadable saved settings fall back to the defaults', () async {
    SharedPreferences.setMockInitialValues({
      'robot_logs_settings': '{not json',
      'robot_logs_catalog': '[{"rel": 1}]',
    });
    final c = controller(FakeRobot({}), FakeLogSite());
    await c.bootstrap();
    expect(c.site, RobotLogsController.defaultSite);
    expect(c.files, isEmpty);
  });

  test(
    'auto mode pulls and sends on its own, and remembers the setting',
    () async {
      final robot = FakeRobot({'/U/logs/a.wpilog': matchLog()});
      final site = FakeLogSite(partSize: 1 << 20);
      final c = RobotLogsController(
        limelights: LimelightApi(client: fakeLimelight(parts)),
        siteHttp: site.client,
        connectRobot: (host, port, {username}) async => robot,
        isOpen: (host, port) async => host == '10.38.47.2',
        defaultFolder: '${dir.path}/logs',
        autoInterval: const Duration(milliseconds: 50),
      )..uploadKey = 'key';
      addTearDown(c.dispose);
      await c.bootstrap();
      await c.setAutoSync(true);
      expect(c.unsentRels, isEmpty);
      expect(site.completed, hasLength(2));

      robot.files['/U/logs/b.wpilog'] = matchLog(matchNumber: 4);
      for (var i = 0; i < 100 && site.completed.length < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(site.completed.keys, contains('3847_TXMAN1_Q4.wpilog'));
      await c.setAutoSync(false);
      while (c.busy || c.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final again = controller(robot, site);
      await again.bootstrap();
      expect(again.autoSync, isFalse);
    },
  );

  test('a catalog entry saved before phases is read again', () async {
    final robot = FakeRobot({'/U/logs/a.wpilog': matchLog()});
    final c = controller(robot, FakeLogSite());
    await c.bootstrap();
    await c.syncAll();
    final rel = c.files.firstWhere((f) => f.kind == RobotLogKind.wpilog).rel;
    await c.rename(rel, 'mine');

    final prefs = await SharedPreferences.getInstance();
    final raw = jsonDecode(prefs.getString('robot_logs_catalog')!) as List;
    for (final e in raw.cast<Map<String, dynamic>>()) {
      e.remove('modifiedMs');
      (e['wpilog'] as Map?)?.remove('phases');
      (e['rwnd'] as Map?)?.remove('fpgaStart');
    }
    await prefs.setString('robot_logs_catalog', jsonEncode(raw));

    final again = controller(robot, FakeLogSite());
    await again.bootstrap();
    final log = again.file(rel)!;
    expect(log.wpilog!.phases.single.end, 160);
    expect(log.name, 'mine.wpilog');
    expect(log.nameEdited, isTrue);
    expect(again.files.every((f) => f.modifiedMs != null), isTrue);
    final rewind = again.files.firstWhere((f) => f.kind == RobotLogKind.rwnd);
    expect(rewind.rwnd!.fpgaStart, 100);
  });

  test('groups a match log with its rewinds', () async {
    final robot = FakeRobot({'/U/logs/a.wpilog': matchLog()});
    final c = controller(robot, FakeLogSite());
    await c.bootstrap();
    await c.syncAll();
    final g = c.groups.single;
    expect(g.title, '3847 TXMAN1 Q3');
    expect(g.logCount, 1);
    expect(g.rewindCount, 1);
    expect(g.sent, isFalse);
  });

  test('an auto run with no robot only checks the robot addresses', () async {
    var probes = 0;
    final c = RobotLogsController(
      limelights: LimelightApi(
        client: MockClient((req) async {
          probes++;
          throw const SocketException('x');
        }),
      ),
      isOpen: (host, port) async => false,
      defaultFolder: '${dir.path}/logs',
    );
    await c.bootstrap();
    await c.syncAll(auto: true);
    expect(probes, 0);
    expect(c.scan!.robots, isEmpty);
    expect(c.job, isNull);
  });

  test('a held auto run waits, and a failed send waits for a click', () async {
    final robot = FakeRobot({'/U/logs/a.wpilog': matchLog()});
    final site = FakeLogSite(partSize: 1 << 20)..status = 500;
    final c = controller(robot, site)..uploadKey = 'key';
    await c.bootstrap();

    c.holdAuto();
    await c.syncAll(auto: true);
    expect(c.scan, isNull);
    c.releaseAuto();

    await c.syncAll(auto: true);
    expect(c.unsentRels, hasLength(2));
    final calls = site.calls.length;
    expect(calls, greaterThan(0));

    await c.syncAll(auto: true);
    expect(site.calls.length, calls);

    site.status = 200;
    await c.syncAll();
    expect(c.unsentRels, isEmpty);
  });
}
