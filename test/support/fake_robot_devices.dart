import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumpit/src/services/robot_devices.dart';
import 'package:spectrumpit/src/state/robot_logs_controller.dart';

class FakeRobot implements RobotShell {
  FakeRobot(this.files);
  final Map<String, List<int>> files;
  int opened = 0;

  @override
  String get username => 'lvuser';

  @override
  Future<List<RobotFile>> listLogs() async => [
    for (final e in files.entries)
      RobotFile(
        path: e.key,
        size: e.value.length,
        modified: DateTime(2026, 10, 16),
      ),
  ];

  @override
  Future<void> download(
    String remote,
    File local, {
    required int size,
    void Function(double)? onProgress,
  }) async {
    await local.parent.create(recursive: true);
    await local.writeAsBytes(files[remote]!);
    onProgress?.call(1);
  }

  @override
  void close() {}
}

MockClient fakeLimelight(Map<String, File> parts) => MockClient((req) async {
  if (req.url.host != 'limelight-left.local') {
    throw const SocketException('no route');
  }
  switch (req.url.path) {
    case '/status':
      return http.Response(jsonEncode({'name': 'limelight-left'}), 200);
    case '/recording-list':
      return http.Response(
        jsonEncode([
          {
            'video': 'rec1.avi',
            'manifest': 'rec1_manifest.jsonl',
            'bootlog': 'rec1_bootlog.txt.gz',
            'size': parts.values.fold<int>(0, (a, f) => a + f.lengthSync()),
          },
        ]),
        200,
      );
  }
  final name = req.url.pathSegments.last;
  return http.Response.bytes(parts[name]!.readAsBytesSync(), 200);
});
