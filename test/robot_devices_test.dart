import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumpit/src/services/robot_devices.dart';

void main() {
  test('team networks and robot addresses', () {
    expect(teamNet(3847), '10.38.47');
    expect(teamNet(8515), '10.85.15');
    expect(teamNet(254), '10.2.54');
    expect(robotHosts(3847).first, '10.38.47.2');
    expect(limelightHosts(3847), contains('10.38.47.19'));
  });

  test('parses a log listing, newest first, without duplicates', () {
    final files = parseLogListing(
      '10 1760000000 /U/logs/a.wpilog\n'
      'junk line\n'
      '20 1760000100 /home/lvuser/logs/it\'s b.wpilog\n'
      '10 1760000000 /U/logs/a.wpilog\n',
    );
    expect(files.map((f) => f.name), ["it's b.wpilog", 'a.wpilog']);
    expect(files.first.size, 20);
  });

  test('quotes a path for the shell', () {
    expect(shellQuote("it's"), r"'it'\''s'");
  });

  test('a recording with an empty part name skips that part', () async {
    final api = LimelightApi(
      client: MockClient((req) async {
        if (req.url.path == '/status') {
          return http.Response(jsonEncode({'name': 'limelight-left'}), 200);
        }
        return http.Response(
          jsonEncode({
            'recordings': [
              {'video': 'a.avi', 'manifest': '', 'bootlog': 'a_bootlog.txt.gz'},
              {'video': ''},
            ],
          }),
          200,
        );
      }),
    );
    final ll = await api.probe('limelight-left.local');
    expect(ll!.recordings.single.parts, ['a.avi', 'a_bootlog.txt.gz']);
  });
}
