import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumpit/src/services/desktop_tray_service.dart';
import 'package:spectrumpit/src/state/theme_controller.dart';
import 'package:spectrumpit/src/state/user_role_controller.dart';
import 'package:spectrumpit/src/ui/settings_tab.dart';

import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSettings(WidgetTester tester) async {
    final themeController = ThemeController();
    await themeController.bootstrap();
    final userRoleController = UserRoleController(
      authService: FakeSpectrumAuthService(),
      roleService: FakeUserRoleService(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsTab(
            themeController: themeController,
            userRoleController: userRoleController,
            authService: FakeSpectrumAuthService(),
          ),
        ),
      ),
    );
  }

  testWidgets('the Liquid Glass card is absent without a glass-capable OS', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.pump();

    expect(find.text('Liquid Glass'), findsNothing);
    expect(find.text('Use Liquid Glass chrome'), findsNothing);
  });

  testWidgets('the Appearance section still renders around the gated tile', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.pump();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
  });

  testWidgets('desktop shows the tray switch, on by default, and saves it', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.pump();

    final tile = find.widgetWithText(
      SwitchListTile,
      'Minimize and close to the tray',
    );
    await tester.scrollUntilVisible(tile, 300);

    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(await MinimizeToTraySetting().isEnabled(), isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('mobile has no tray switch', (tester) async {
    await pumpSettings(tester);
    await tester.pump();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
    await tester.pump();
    expect(find.text('Minimize and close to the tray'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
