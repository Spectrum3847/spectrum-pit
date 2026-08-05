import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/user_role.dart';
import 'package:spectrumpit/src/ui/docs_viewer_screen.dart';

void main() {
  testWidgets('docs tab lists grouped docs (developer sees all)', (
    tester,
  ) async {
    // A developer sees every doc, so the list is long; give it a tall surface
    // so the lazy ListView builds all rows and the assertions below can find
    // groups near the bottom (Reference, Developer reference).
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocsTab(roles: {UserRole.developer})),
      ),
    );

    expect(find.text('Start here'), findsOneWidget); // group header
    expect(find.text('Developer reference'), findsOneWidget);
    expect(find.text('Reference'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    // Developer/reference docs are all visible to a developer.
    expect(find.text('Developer Manual'), findsOneWidget);
    expect(find.text('CI Workflows'), findsOneWidget);
    expect(find.text('Upstream'), findsOneWidget);
  });

  testWidgets('docs are role-filtered: a pit member sees only member docs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocsTab(roles: {UserRole.pit})),
      ),
    );

    // The Overview is visible to every member.
    expect(find.text('Overview'), findsOneWidget);
    // Developer-only docs and their group headers are hidden from pit members.
    expect(find.text('Developer Manual'), findsNothing);
    expect(find.text('CI Workflows'), findsNothing);
    expect(find.text('Developer reference'), findsNothing);
    expect(find.text('Reference'), findsNothing); // whole group hidden
  });

  testWidgets('tapping a doc opens the renderer with bundled content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocsTab(roles: {UserRole.developer})),
      ),
    );

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // Navigated to the DocPage: the index group headers are gone and the
    // doc title shows in the app bar.
    expect(find.text('Start here'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Overview'), findsOneWidget);
    // The asset finished loading: no spinner, and the Markdown actually
    // rendered (not stuck on a loading or error state).
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Markdown), findsOneWidget);
  });
}
