import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
