import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/services/debug_info.dart';
import 'package:spectrumpit/src/services/telemetry_service.dart';

// Every field the Firestore rules' isValidTelemetry allows.
const _allowedKeys = {
  'id',
  'type',
  'deviceId',
  'appVersion',
  'platform',
  'osVersion',
  'locale',
  'detail',
  'createdAt',
};

const _info = DebugInfo(
  appVersion: '1.2.3',
  buildNumber: '7',
  platform: 'linux',
  osVersion: 'Linux test',
  device: 'Test PC',
  gitCommit: 'abc1234',
  gitBranch: 'master',
  buildDate: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('logEvent writes a telemetry doc within the rules whitelist', () async {
    final firestore = FakeFirebaseFirestore();
    final service = TelemetryService(
      firestore: firestore,
      debugInfo: () async => _info,
    );
    await service.setEnabled(true);

    // A detail makes every optional key present, so the written key set is
    // exactly the full whitelist below.
    await service.logEvent('app_open', detail: 'first-launch');

    final snap = await firestore.collection('telemetry').get();
    expect(snap.docs, hasLength(1));
    final data = snap.docs.single.data();

    // Exact set equality against isValidTelemetry's whitelist (firestore.rules):
    // if the rules' required fields change, this expected set must change too.
    expect(data.keys.toSet(), _allowedKeys);
    expect(data['type'], 'app_open');
    expect(data['deviceId'], isNotEmpty);
    expect(data['platform'], 'linux');
    expect(data['appVersion'], contains('1.2.3'));
    expect(data['id'], snap.docs.single.id);
    expect(data['detail'], 'first-launch');
    final createdAt = data['createdAt'] as String;
    expect(DateTime.tryParse(createdAt), isNotNull);
  });

  test(
    'logEvent clamps over-length type and detail to the rule bounds',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = TelemetryService(
        firestore: firestore,
        debugInfo: () async => _info,
      );
      await service.setEnabled(true);

      await service.logEvent('x' * 200, detail: 'y' * 500);

      final data = (await firestore.collection('telemetry').get()).docs.single
          .data();
      // Persisted values are clamped, not just the in-memory inputs.
      expect((data['type'] as String).length, 64);
      expect((data['detail'] as String).length, 128);
    },
  );

  test('logEvent is a no-op when telemetry is disabled', () async {
    final firestore = FakeFirebaseFirestore();
    final service = TelemetryService(
      firestore: firestore,
      debugInfo: () async => _info,
    );

    await service.setEnabled(false);
    await service.logEvent('app_open');

    expect((await firestore.collection('telemetry').get()).docs, isEmpty);
  });

  test('the device id is stable across events and persists', () async {
    final firestore = FakeFirebaseFirestore();
    TelemetryService make() =>
        TelemetryService(firestore: firestore, debugInfo: () async => _info);

    final first = make();
    await first.setEnabled(true);
    await first.logEvent('app_open');
    await make().logEvent('tab_open', detail: 'Strategy');

    final docs = (await firestore.collection('telemetry').get()).docs;
    expect(docs, hasLength(2));
    final ids = docs.map((d) => d.data()['deviceId']).toSet();
    // A fresh instance reads the same persisted id, so only one distinct value.
    expect(ids, hasLength(1));
  });

  test('setEnabled persists and gates a later instance', () async {
    await TelemetryService().setEnabled(false);
    expect(await TelemetryService().isEnabled(), isFalse);
  });

  test('an injected REST writer gets the same doc and detail (#570)', () async {
    String? path;
    Map<String, dynamic>? written;
    final service = TelemetryService(
      debugInfo: () async => _info,
      write: (docPath, data) async {
        path = docPath;
        written = data;
      },
    );
    await service.setEnabled(true);

    await service.logEvent('tab_open', detail: 'Prematch');

    expect(path, 'telemetry/${written!['id']}');
    expect(written!['type'], 'tab_open');
    expect(written!['detail'], 'Prematch');
  });

  // #169: the stored preference has three states and only null means "never
  // touched". false and null both mean "not collecting" now, but Settings shows
  // them differently, so a refusal that decayed back to null would read as an
  // untouched install and flip collection back on.
  group('storedPreference after a change', () {
    test('is false after the toggle is turned off, not null', () async {
      final service = TelemetryService(
        firestore: FakeFirebaseFirestore(),
        debugInfo: () async => _info,
      );
      await service.setEnabled(false);

      expect(await service.storedPreference(), isFalse);
    });

    test('a later change replaces the earlier answer', () async {
      final service = TelemetryService(
        firestore: FakeFirebaseFirestore(),
        debugInfo: () async => _info,
      );
      await service.setEnabled(true);
      await service.setEnabled(false);

      expect(await service.storedPreference(), isFalse);
    });
  });

  // #168: the maintainer's call is that both apps behave the same, and Strategy
  // is opt-out. So an untouched install collects, and the Settings toggle is how
  // somebody turns it off.
  group('opt-out default', () {
    test('an untouched install is enabled', () async {
      expect(await TelemetryService().isEnabled(), isTrue);
    });

    test('turning it off sticks', () async {
      await TelemetryService().setEnabled(false);
      expect(await TelemetryService().isEnabled(), isFalse);
    });

    test('storedPreference is null until the toggle is touched', () async {
      // Settings uses this to tell "on by default" from "deliberately on".
      // Nothing prompts on it any more.
      expect(await TelemetryService().storedPreference(), isNull);
      await TelemetryService().setEnabled(true);
      expect(await TelemetryService().storedPreference(), isTrue);
    });
  });

  test('an untouched install actually transmits', () async {
    // isEnabled and logEvent read the same preference separately, and flipping
    // only one left collection off for every untouched install while the toggle
    // claimed otherwise (#168).
    final firestore = FakeFirebaseFirestore();
    final service = TelemetryService(
      firestore: firestore,
      debugInfo: () async => _info,
    );

    await service.logEvent('app_open');

    final snap = await firestore.collection('telemetry').get();
    expect(snap.docs, hasLength(1));
  });

  test('turning it off stops transmission', () async {
    final firestore = FakeFirebaseFirestore();
    final service = TelemetryService(
      firestore: firestore,
      debugInfo: () async => _info,
    );
    await service.setEnabled(false);

    await service.logEvent('app_open');

    expect((await firestore.collection('telemetry').get()).docs, isEmpty);
  });
}
