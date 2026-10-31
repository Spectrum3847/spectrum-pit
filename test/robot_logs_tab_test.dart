import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/services/robot_devices.dart';
import 'package:spectrumpit/src/state/robot_logs_controller.dart';
import 'package:spectrumpit/src/theme/app_theme.dart';
import 'package:spectrumpit/src/ui/robot_logs_tab.dart';

import 'support/fake_log_site.dart';
import 'support/fake_robot_devices.dart';
import 'support/robot_log_fixtures.dart';

void main() {
  late Directory dir;
  late FakeLogSite site;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('robot_logs_tab');
    site = FakeLogSite(partSize: 1 << 20);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  RobotLogsController make({bool robot = true}) {
    final partsDir = Directory('${dir.path}/fixture')..createSync();
    final parts = {
      for (final f in writeRecordingParts(partsDir)) f.uri.pathSegments.last: f,
    };
    final fake = FakeRobot({
      '/U/logs/FRC_20261016_101256_TXMAN1_Q3.wpilog': matchLog(),
    });
    return RobotLogsController(
      limelights: LimelightApi(client: fakeLimelight(parts)),
      siteHttp: site.client,
      connectRobot: (host, port, {username}) async => fake,
      isOpen: (host, port) async => robot && host == '10.38.47.2',
      defaultFolder: '${dir.path}/logs',
    );
  }

  Future<void> pump(
    WidgetTester tester,
    RobotLogsController c, {
    Size size = const Size(1280, 900),
    double text = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(text)),
          child: child!,
        ),
        home: Scaffold(body: RobotLogsTab(controller: c)),
      ),
    );
    await tester.pump();
  }

  testWidgets('starts empty and asks for the upload key', (tester) async {
    final c = make();
    await tester.runAsync(c.bootstrap);
    await pump(tester, c);
    expect(find.text('Pull and send everything new'), findsOneWidget);
    expect(find.textContaining('Plug this laptop into the robot'), findsOne);
    expect(find.text('Add key'), findsOneWidget);
    expect(find.textContaining('Nothing pulled yet'), findsOneWidget);
  });

  testWidgets('one click pulls, names, groups and sends by match', (
    tester,
  ) async {
    final c = make()..uploadKey = 'key';
    await tester.runAsync(() async {
      await c.bootstrap();
      await c.syncAll();
    });
    await pump(tester, c);
    expect(site.completed.keys, [
      '3847_TXMAN1_Q3.wpilog',
      '3847_TXMAN1_Q3_limelight-left.rwnd',
    ]);
    expect(find.text('3847 TXMAN1 Q3'), findsOneWidget);
    expect(find.textContaining('1 log + 1 rewind'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.textContaining('Robot 3847 connected, 1 camera'), findsOne);
    expect(find.text('Add key'), findsNothing);

    await tester.tap(find.text('3847 TXMAN1 Q3'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        '3847_TXMAN1_Q3_limelight-left.rwnd',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('without a key files are copied but not sent', (tester) async {
    final c = make();
    await tester.runAsync(() async {
      await c.bootstrap();
      await c.syncAll();
    });
    await pump(tester, c);
    expect(site.calls, isEmpty);
    expect(find.text('Not sent'), findsOneWidget);
  });

  testWidgets('says when no robot answers', (tester) async {
    final c = make(robot: false);
    await tester.runAsync(() async {
      await c.bootstrap();
      await c.scanDevices();
    });
    await pump(tester, c);
    expect(find.textContaining('No robot found on 10.38.47.x'), findsOne);
  });

  testWidgets('holds up at 200% text on a small laptop window', (tester) async {
    final c = make()..uploadKey = 'key';
    await tester.runAsync(() async {
      await c.bootstrap();
      await c.syncAll();
    });
    await pump(tester, c, size: const Size(800, 600), text: 2);
    expect(tester.takeException(), isNull);
  });
}
