import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:spectrumpit/src/services/photo_service.dart';

import 'support/photo_test_support.dart';

Uint8List _bytes(int length, [int fill = 7]) =>
    Uint8List.fromList(List<int>.filled(length, fill));

PickedPhoto _photo({int length = 32, String type = 'image/jpeg'}) =>
    PickedPhoto(bytes: _bytes(length), contentType: type);

void main() {
  test('upload returns the key the Worker minted', () async {
    final requests = <http.BaseRequest>[];
    final service = fakePhotoService(requests: requests);

    final key = await service.upload(_photo(type: 'image/png'));

    expect(key, 'key-0.jpg');
    expect(requests.single.method, 'POST');
    expect(requests.single.headers['Authorization'], 'Bearer test-token');
    expect(requests.single.headers['Content-Type'], 'image/png');
  });

  test('upload seeds the cache, so the first fetch needs no request', () async {
    final requests = <http.BaseRequest>[];
    final service = fakePhotoService(requests: requests);

    final key = await service.upload(_photo());
    expect(await service.fetch(key), _bytes(32));

    expect(requests.map((r) => r.method), ['POST']);
  });

  test('upload refuses more than 2 MB before sending anything', () async {
    final requests = <http.BaseRequest>[];
    final service = fakePhotoService(requests: requests);

    await expectLater(
      service.upload(_photo(length: PhotoService.maxBytes + 1)),
      throwsA(
        isA<PhotoException>().having(
          (e) => e.message,
          'message',
          allOf(contains('2 MB'), contains('Resize')),
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('upload refuses an empty file', () async {
    final service = fakePhotoService();
    await expectLater(
      service.upload(_photo(length: 0)),
      throwsA(isA<PhotoException>()),
    );
  });

  test('a write with no ID token throws instead of failing silently', () async {
    final service = unavailablePhotoService();
    await expectLater(
      service.upload(_photo()),
      throwsA(
        isA<PhotoException>().having(
          (e) => e.message,
          'message',
          contains('Sign in'),
        ),
      ),
    );
    await expectLater(
      service.delete('key-0.jpg'),
      throwsA(isA<PhotoException>()),
    );
  });

  test('a read with no ID token degrades to null', () async {
    expect(await unavailablePhotoService().fetch('key-0.jpg'), isNull);
  });

  test('fetch serves repeat reads from the cache', () async {
    final requests = <http.BaseRequest>[];
    final service = fakePhotoService(
      stored: {'a.jpg': _bytes(4)},
      requests: requests,
    );

    expect(await service.fetch('a.jpg'), _bytes(4));
    expect(await service.fetch('a.jpg'), _bytes(4));

    expect(requests.length, 1);
  });

  test('the cache evicts the least recently used key past its bound', () async {
    final requests = <http.BaseRequest>[];
    final service = fakePhotoService(
      stored: {'a.jpg': _bytes(1), 'b.jpg': _bytes(2), 'c.jpg': _bytes(3)},
      requests: requests,
      cacheLimit: 2,
    );

    await service.fetch('a.jpg');
    await service.fetch('b.jpg');
    // Touching a.jpg makes b.jpg the oldest, so caching c.jpg evicts b.jpg.
    await service.fetch('a.jpg');
    await service.fetch('c.jpg');
    expect(requests.length, 3);

    await service.fetch('a.jpg');
    expect(requests.length, 3, reason: 'a.jpg was still cached');
    await service.fetch('b.jpg');
    expect(requests.length, 4, reason: 'b.jpg was evicted');
  });

  test('a missing key reports that the photo is gone', () async {
    final service = fakePhotoService();
    await expectLater(
      service.fetch('gone.jpg'),
      throwsA(
        isA<PhotoException>().having(
          (e) => e.message,
          'message',
          contains('no longer in storage'),
        ),
      ),
    );
  });

  test('a refused request names the role problem', () async {
    final service = fakePhotoService(
      respond: (_) => http.Response('{"error":"Not a member"}', 403),
    );
    await expectLater(
      service.fetch('a.jpg'),
      throwsA(
        isA<PhotoException>().having(
          (e) => e.message,
          'message',
          contains('team role'),
        ),
      ),
    );
  });

  test('an unexpected status carries the code', () async {
    final service = fakePhotoService(
      respond: (_) => http.Response('boom', 500),
    );
    await expectLater(
      service.fetch('a.jpg'),
      throwsA(
        isA<PhotoException>().having(
          (e) => e.message,
          'message',
          contains('500'),
        ),
      ),
    );
  });

  test('delete drops the key and its cached bytes', () async {
    final stored = {'a.jpg': _bytes(4)};
    final requests = <http.BaseRequest>[];
    final service = fakePhotoService(stored: stored, requests: requests);

    await service.fetch('a.jpg');
    await service.delete('a.jpg');

    expect(stored, isEmpty);
    expect(requests.last.method, 'DELETE');
    // The cache must not keep serving bytes that no longer exist.
    await expectLater(service.fetch('a.jpg'), throwsA(isA<PhotoException>()));
  });

  test('deleting a key that is already gone counts as removed', () async {
    await fakePhotoService().delete('gone.jpg');
  });

  test('capture uploads what the picker returns, and nothing when it is '
      'cancelled', () async {
    final cancelled = fakePhotoService(picker: (_) async => null);
    expect(await cancelled.capture(PhotoSource.camera), isNull);

    final service = fakePhotoService(picker: (_) async => _photo());
    expect(await service.capture(PhotoSource.camera), 'key-0.jpg');
  });

  test('pickImage hands each platform its own source, returns the bytes, and '
      'never uploads', () async {
    // Restore the platform override even if an expectation fails below.
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final (platform, expected) in [
      (TargetPlatform.iOS, PhotoSource.gallery),
      (TargetPlatform.linux, PhotoSource.file),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      final requests = <http.BaseRequest>[];
      PhotoSource? source;
      final photo = _photo();
      final service = fakePhotoService(
        requests: requests,
        picker: (pickedSource) async {
          source = pickedSource;
          return photo;
        },
      );
      final picked = await service.pickImage();
      expect(source, expected);
      expect(picked, isNotNull);
      expect(picked!.bytes, photo.bytes);
      expect(requests, isEmpty);
    }

    final cancelled = fakePhotoService(picker: (_) async => null);
    expect(await cancelled.pickImage(), isNull);
  });

  test('sources follow the platform: camera on mobile, files elsewhere', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = fakePhotoService();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(service.sources, [PhotoSource.camera, PhotoSource.gallery]);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(service.sources, [PhotoSource.file]);
  });
}
