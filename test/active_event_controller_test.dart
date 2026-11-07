import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/models/active_event.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/active_event_controller.dart';

import 'support/fake_active_event_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';

const _user = SpectrumUser(uid: 'uid-1', displayName: 'Sam', email: 's@x.org');

final _houston = ActiveEvent(
  eventKey: '2026txhou',
  eventName: 'Houston',
  updatedAt: DateTime.utc(2026, 4, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeActiveEventSyncService sync;

  setUp(() {
    sync = FakeActiveEventSyncService();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ActiveEventController build({SpectrumUser? user = _user}) =>
      ActiveEventController(
        authService: FakeSpectrumAuthService(initialUser: user),
        syncService: sync,
        clock: () => DateTime.utc(2026, 4, 2),
      );

  test('serves the cached event before any server read', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ActiveEventController.cacheKey: jsonEncode(_houston.toJson()),
    });
    final controller = build(user: null);
    addTearDown(controller.dispose);
    await controller.bootstrap();

    expect(controller.event, _houston);
  });

  test('follows the server and caches what it sends', () async {
    final controller = build();
    addTearDown(controller.dispose);
    await controller.bootstrap();

    sync.emit(_houston);
    await pumpEventQueue();
    expect(controller.event, _houston);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ActiveEventController.cacheKey),
      jsonEncode(_houston.toJson()),
    );

    sync.emit(null);
    await pumpEventQueue();
    expect(controller.event, isNull);
  });

  test('select shows the event and writes it for every device', () async {
    final controller = build();
    addTearDown(controller.dispose);
    await controller.bootstrap();

    await controller.select(eventKey: '2026txcl2', eventName: 'Central');

    expect(controller.event?.eventKey, '2026txcl2');
    expect(sync.writes.single.eventName, 'Central');
    expect(sync.writes.single.updatedAt, DateTime.utc(2026, 4, 2));
  });

  test('a failed write rolls back and rethrows', () async {
    final controller = build();
    addTearDown(controller.dispose);
    await controller.bootstrap();
    sync.emit(_houston);
    await pumpEventQueue();

    sync.failWith = StateError('offline');
    await expectLater(
      controller.select(eventKey: '2026txcl2', eventName: 'Central'),
      throwsStateError,
    );
    expect(controller.event, _houston);
  });
}
