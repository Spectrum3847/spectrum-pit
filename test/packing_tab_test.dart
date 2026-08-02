import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumpit/src/models/packing_record.dart';
import 'package:spectrumpit/src/services/photo_service.dart';
import 'package:spectrumpit/src/services/spectrum_auth_service.dart';
import 'package:spectrumpit/src/state/packing_controller.dart';
import 'package:spectrumpit/src/ui/packing_tab.dart';

import 'support/fake_packing_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/photo_test_support.dart';

const _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

PackingRecord _record(
  String id, {
  String itemId = 'Drill',
  PackingStatus status = PackingStatus.packing,
  String? photoRef,
}) => PackingRecord(
  id: id,
  itemId: itemId,
  packingStatus: status,
  photoRef: photoRef,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<PackingController> _makeController({
  List<PackingRecord> initial = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sync = FakePackingSyncService();
  final controller = PackingController(
    authService: FakeSpectrumAuthService(initialUser: _user),
    syncService: sync,
  );
  await controller.bootstrap();
  if (initial.isNotEmpty) sync.emit(initial);
  return controller;
}

Widget _wrap(PackingController controller, {PhotoService? photoService}) =>
    MaterialApp(
      // No ink splash: the test engine's shader format does not match it.
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: PackingTab(
          controller: controller,
          photoService: photoService ?? unavailablePhotoService(),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state shows the dashed board and add button', (
    tester,
  ) async {
    final controller = await _makeController();
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('The packing list is empty'), findsOneWidget);
    expect(find.text('Add item'), findsWidgets);
    controller.dispose();
  });

  testWidgets('items are displayed in a list', (tester) async {
    final controller = await _makeController(
      initial: [
        _record('a', itemId: 'Drill Kit'),
        _record('b', itemId: 'Soldering Iron'),
      ],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('Drill Kit'), findsOneWidget);
    expect(find.text('Soldering Iron'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('status chip shows the correct label', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', status: PackingStatus.staging)],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('Staging'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('tapping status chip advances the pipeline', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', status: PackingStatus.packing)],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.text('Packing'), findsOneWidget);
    await tester.tap(find.text('Packing'));
    await tester.pumpAndSettle();

    expect(controller.items.single.packingStatus, PackingStatus.staging);
    expect(find.text('Staging'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('FAB opens the add editor', (tester) async {
    final controller = await _makeController();
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add packing item'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    controller.dispose();
  });

  testWidgets('add editor creates a new record', (tester) async {
    final controller = await _makeController();
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Wrench Set');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add item').last);
    await tester.pumpAndSettle();

    expect(controller.items.length, 1);
    expect(controller.items.single.itemId, 'Wrench Set');
    controller.dispose();
  });

  testWidgets('add button is disabled when name is empty', (tester) async {
    final controller = await _makeController();
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add item').last,
    );
    // The save button should be disabled when the text field is empty.
    expect(button.onPressed, isNull);
    controller.dispose();
  });

  testWidgets('tapping a row opens the edit editor', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', itemId: 'Drill')],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drill'));
    await tester.pumpAndSettle();

    expect(find.text('Edit packing item'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    controller.dispose();
  });

  testWidgets('a record with no photo shows the capture affordance', (
    tester,
  ) async {
    final controller = await _makeController(initial: [_record('a')]);
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
    expect(find.byTooltip('Add a packing photo'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('an attached photo renders as a thumbnail', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    await tester.pumpWidget(
      _wrap(
        controller,
        photoService: fakePhotoService(stored: {'a.jpg': tinyPng}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
    expect(find.byTooltip('Open the packing photo'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('a photo that will not load offers a retry', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    await tester.pumpWidget(
      _wrap(
        controller,
        photoService: fakePhotoService(
          respond: (_) => http.Response('boom', 500),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(
      find.byTooltip('Photo did not load. Tap to try again.'),
      findsOneWidget,
    );
    controller.dispose();
  });

  testWidgets('photos degrade to an unavailable slot with no ID token', (
    tester,
  ) async {
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    controller.dispose();
  });

  testWidgets('tapping the empty slot captures and attaches the photo', (
    tester,
  ) async {
    // Desktop offers one capture source, so the tap goes straight to the
    // picker with no source sheet in between.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final controller = await _makeController(initial: [_record('a')]);
    await tester.pumpWidget(
      _wrap(
        controller,
        photoService: fakePhotoService(
          picker: (_) async =>
              PickedPhoto(bytes: tinyPng, contentType: 'image/png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_a_photo_outlined));
    await tester.pumpAndSettle();
    // The binding checks this before tearDown callbacks run, so it cannot be
    // reset with addTearDown.
    debugDefaultTargetPlatformOverride = null;

    expect(controller.items.single.photoRef, 'key-0.jpg');
    expect(find.byType(Image), findsOneWidget);
    controller.dispose();
  });

  testWidgets('the viewer removes the photo and its stored key', (
    tester,
  ) async {
    final stored = {'a.jpg': tinyPng};
    final controller = await _makeController(
      initial: [_record('a', photoRef: 'a.jpg')],
    );
    await tester.pumpWidget(
      _wrap(controller, photoService: fakePhotoService(stored: stored)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open the packing photo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Replace'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(controller.items.single.photoRef, isNull);
    expect(stored, isEmpty);
    controller.dispose();
  });

  testWidgets('delete button removes the record', (tester) async {
    final controller = await _makeController(
      initial: [_record('a', itemId: 'Drill')],
    );
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drill'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    // Confirm dialog
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(controller.items, isEmpty);
    controller.dispose();
  });

  testWidgets('a photo captured in the add editor lands on the new record', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final controller = await _makeController();
    await tester.pumpWidget(
      _wrap(
        controller,
        photoService: fakePhotoService(
          picker: (_) async =>
              PickedPhoto(bytes: tinyPng, contentType: 'image/png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // The editor sheet's empty photo affordance offers capture.
    expect(find.text('Add packing item'), findsOneWidget);
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();

    // Name the item and save; the returned photoRef rides along.
    await tester.enterText(find.byType(TextField), 'Wrench Set');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add item').last);
    await tester.pumpAndSettle();

    debugDefaultTargetPlatformOverride = null;

    expect(controller.items.length, 1);
    expect(controller.items.single.itemId, 'Wrench Set');
    expect(controller.items.single.photoRef, 'key-0.jpg');
    controller.dispose();
  });
}
