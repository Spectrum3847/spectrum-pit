import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/rwnd_file.dart';

import 'support/robot_log_fixtures.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rwnd_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  File build({required bool withIdx1}) {
    final parts = writeRecordingParts(dir, frames: 4, withIdx1: withIdx1);
    final out = File('${dir.path}/rec.rwnd');
    writeStoredZip(out, [for (final p in parts) (p.uri.pathSegments.last, p)]);
    return out;
  }

  for (final withIdx1 in [true, false]) {
    test('indexes every frame of a rewind (idx1: $withIdx1)', () {
      final file = build(withIdx1: withIdx1);
      final a = analyzeRwnd(file);
      final frames = a.index['frames'] as Map<String, dynamic>;
      final offsets = frames['offset'] as List<int>;
      final sizes = frames['size'] as List<int>;
      expect(offsets, hasLength(4));
      final bytes = file.readAsBytesSync();
      for (var i = 0; i < offsets.length; i++) {
        expect(bytes.sublist(offsets[i], offsets[i] + 2), [0xff, 0xd8]);
        expect(
          bytes.sublist(offsets[i] + sizes[i] - 2, offsets[i] + sizes[i]),
          [0xff, 0xd9],
        );
      }
      expect(a.camera, 'limelight-left');
      expect(a.team, 3847);
      expect(a.summary['frames'], 4);
      expect(a.summary['fps'], 30);
      expect(a.summary['width'], 640);
      expect(a.summary['targetPct'], 50);
      expect(a.unixMs, [1760630000000, 1760630000100]);
      expect(a.fpga, [100, 100.099999]);
      final cols = a.index['cols'] as Map<String, List<Object?>>;
      expect(cols['tags']!.first, [7]);
      expect(cols['lat']!.first, 15.75);
      expect(cols['x']!.first, 1.235);
      expect(cols['x1']!.first, isNull);
    });
  }

  test('reads the team out of a boot log', () {
    expect(teamFromText('a 10.85.15.11 b 10.85.15.2 c 10.38.47.2'), 8515);
    expect(teamFromText('no address'), isNull);
  });

  test('falls back to the file name for the camera', () {
    expect(cameraFromName('Q3_TURRET.rwnd'), 'limelight-turret');
    expect(cameraFromName('x_limelight-back_y.rwnd'), 'limelight-back');
    expect(cameraFromName('capture.rwnd'), isNull);
  });

  test('rejects a file that is not a zip', () {
    final f = File('${dir.path}/bad.rwnd')..writeAsStringSync('nope');
    expect(() => analyzeRwnd(f), throwsFormatException);
  });
}
