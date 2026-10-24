import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/services/log_site_client.dart';

import 'support/fake_log_site.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('site_test');
    file = File('${dir.path}/a.wpilog')
      ..writeAsBytesSync(List.generate(10, (i) => i));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  LogSiteClient client(FakeLogSite site) => LogSiteClient(
    site: 'https://logs.example/',
    key: 'k',
    client: site.client,
    retryDelay: Duration.zero,
  );

  test('uploads in parts, then the index, then completes', () async {
    final site = FakeLogSite();
    final progress = <double>[];
    final res = await client(site).upload(
      file,
      name: 'n.rwnd',
      kind: 'rwnd',
      filing: {'camera': 'limelight-left'},
      index: {'version': 1},
      onProgress: progress.add,
    );
    expect(site.calls, [
      'POST uploads',
      'PUT uploads/f0/part/1',
      'PUT uploads/f0/part/2',
      'PUT uploads/f0/part/3',
      'PUT files/f0/index',
      'POST uploads/f0/complete',
    ]);
    expect(site.key, 'k');
    expect([
      ...site.parts[1]!,
      ...site.parts[2]!,
      ...site.parts[3]!,
    ], List.generate(10, (i) => i));
    expect(site.completed['n.rwnd']!['camera'], 'limelight-left');
    expect(site.completed['n.rwnd']!['parts'], hasLength(3));
    expect(res.matchId, 'match-f0');
    expect(res.duplicate, isFalse);
    expect(progress.last, 1);
  });

  test('a file the site already has is not sent again', () async {
    final site = FakeLogSite(duplicateNames: {'n.wpilog'});
    final res = await client(site)
        .upload(file, name: 'n.wpilog', kind: 'wpilog', filing: {});
    expect(res.duplicate, isTrue);
    expect(res.matchId, 'm0');
    expect(site.calls, ['POST uploads']);
  });

  test('retries a failed part', () async {
    final site = FakeLogSite(partSize: 100)..failPartTimes = 2;
    await client(site)
        .upload(file, name: 'n.wpilog', kind: 'wpilog', filing: {});
    expect(site.calls.where((c) => c.contains('part')), hasLength(3));
  });

  test('gives up after four tries and aborts the upload', () async {
    final site = FakeLogSite(partSize: 100)..failPartTimes = 9;
    await expectLater(
      client(site).upload(file, name: 'n.wpilog', kind: 'wpilog', filing: {}),
      throwsA(isA<LogSiteException>()),
    );
    expect(site.calls.where((c) => c.contains('part')), hasLength(4));
    expect(site.calls.last, 'DELETE uploads/f0');
  });

  test('checkKey reports a rejected key as 401', () async {
    final site = FakeLogSite()..status = 401;
    await expectLater(
      client(site).checkKey(),
      throwsA(isA<LogSiteException>().having((e) => e.status, 'status', 401)),
    );
  });
}
