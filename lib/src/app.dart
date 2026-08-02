import 'package:flutter/material.dart';

import 'services/issue_report_service.dart';
import 'services/map_image_store.dart';
import 'services/photo_service.dart';
import 'services/telemetry_service.dart';
import 'services/spectrum_auth_service.dart';
import 'state/borrow_controller.dart';
import 'state/inventory_controller.dart';
import 'state/map_location_controller.dart';
import 'state/packing_controller.dart';
import 'state/pit_shift_controller.dart';
import 'state/theme_controller.dart';
import 'state/user_role_controller.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';

class StrategyApp extends StatefulWidget {
  const StrategyApp({
    required this.authService,
    required this.themeController,
    required this.userRoleController,
    required this.inventoryController,
    required this.packingController,
    required this.borrowController,
    required this.mapLocationController,
    required this.mapImageStore,
    required this.photoService,
    required this.pitShiftController,
    this.issueReportService,
    this.telemetryService,
    super.key,
  });

  final SpectrumAuthService authService;
  final ThemeController themeController;
  final UserRoleController userRoleController;
  final InventoryController inventoryController;
  final PackingController packingController;
  final BorrowController borrowController;
  final MapLocationController mapLocationController;
  final MapImageStore mapImageStore;
  final PhotoService photoService;
  final PitShiftController pitShiftController;
  final IssueReportService? issueReportService;
  final TelemetryService? telemetryService;

  @override
  State<StrategyApp> createState() => _StrategyAppState();
}

class _StrategyAppState extends State<StrategyApp> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    widget.themeController.addListener(_onThemeChanged);
    _bootstrapFuture = _startBootstrap();
  }

  Future<void> _startBootstrap() {
    return Future.wait(<Future<void>>[
      widget.authService.initialize(),
      widget.themeController.bootstrap(),
      widget.userRoleController.bootstrap(),
      widget.inventoryController.bootstrap(),
      widget.packingController.bootstrap(),
      widget.borrowController.bootstrap(),
      widget.mapLocationController.bootstrap(),
      widget.pitShiftController.bootstrap(),
    ]);
  }

  void _retryBootstrap() {
    setState(() {
      _bootstrapFuture = _startBootstrap();
    });
  }

  void _onThemeChanged() => setState(() {});

  @override
  void dispose() {
    widget.themeController.removeListener(_onThemeChanged);
    widget.authService.dispose();
    widget.themeController.dispose();
    widget.userRoleController.dispose();
    widget.inventoryController.dispose();
    widget.packingController.dispose();
    widget.borrowController.dispose();
    widget.mapLocationController.dispose();
    widget.photoService.close();
    widget.pitShiftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spectrum Pit',
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: widget.themeController.themeMode,
      home: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BootstrapErrorScreen(
              error: snapshot.error!,
              onRetry: _retryBootstrap,
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AppShell(
            authService: widget.authService,
            themeController: widget.themeController,
            userRoleController: widget.userRoleController,
            inventoryController: widget.inventoryController,
            packingController: widget.packingController,
            borrowController: widget.borrowController,
            mapLocationController: widget.mapLocationController,
            mapImageStore: widget.mapImageStore,
            photoService: widget.photoService,
            pitShiftController: widget.pitShiftController,
            issueReportService: widget.issueReportService,
            telemetryService: widget.telemetryService,
          );
        },
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Spectrum Pit could not start',
                  style: textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
