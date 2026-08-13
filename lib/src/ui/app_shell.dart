import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/container_photo_sync_service.dart';
import '../services/issue_report_service.dart';
import '../services/map_image_store.dart';
import '../services/photo_service.dart';
import '../services/spectrum_auth_service.dart';
import '../services/telemetry_service.dart';
import '../state/borrow_controller.dart';
import '../state/inventory_controller.dart';
import '../state/map_location_controller.dart';
import '../state/packing_controller.dart';
import '../state/pit_shift_controller.dart';
import '../state/theme_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/pit_palette.dart';
import '../models/user_role.dart';
import 'borrow_tab.dart';
import 'docs_viewer_screen.dart';
import 'inventory_tab.dart';
import 'maps_tab.dart';
import 'packing_tab.dart';
import 'schedule_tab.dart';
import 'settings_tab.dart';
import 'sign_in_screen.dart';
import 'user_management_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.authService,
    required this.themeController,
    required this.userRoleController,
    required this.inventoryController,
    required this.packingController,
    required this.borrowController,
    required this.mapLocationController,
    required this.mapImageStore,
    required this.containerPhotoSyncService,
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
  final ContainerPhotoSyncService containerPhotoSyncService;
  final PhotoService photoService;
  final PitShiftController pitShiftController;
  final IssueReportService? issueReportService;
  final TelemetryService? telemetryService;

  @override
  State<AppShell> createState() => _AppShellState();
}

const _kFirstSecondaryTab = AppTabs.docs;

const _kTabMeta = [
  (
    label: 'Inventory',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
  ),
  (
    label: 'Packing',
    icon: Icons.local_shipping_outlined,
    selectedIcon: Icons.local_shipping_rounded,
  ),
  (
    label: 'Borrowed',
    icon: Icons.handshake_outlined,
    selectedIcon: Icons.handshake_rounded,
  ),
  (label: 'Maps', icon: Icons.map_outlined, selectedIcon: Icons.map_rounded),
  (
    label: 'Schedule',
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note_rounded,
  ),
  (
    label: 'Docs',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book_rounded,
  ),
  (
    label: 'Users',
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts_rounded,
  ),
  (
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
];

class _AppShellState extends State<AppShell> {
  int _index = 0;

  Timer? _overdueTick;

  @override
  void initState() {
    super.initState();
    widget.userRoleController.addListener(_onRoleChanged);
    widget.borrowController.addListener(_onBorrowChanged);
    _overdueTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _clampIndex();
  }

  @override
  void dispose() {
    widget.userRoleController.removeListener(_onRoleChanged);
    widget.borrowController.removeListener(_onBorrowChanged);
    _overdueTick?.cancel();
    super.dispose();
  }

  List<int> get _visibleTabIndices =>
      widget.userRoleController.visibleTabIndices;

  List<int> get _featureTabIndices =>
      _visibleTabIndices.where((i) => i < _kFirstSecondaryTab).toList();

  List<int> get _secondaryTabIndices =>
      _visibleTabIndices.where((i) => i >= _kFirstSecondaryTab).toList();

  void _clampIndex() {
    final features = _featureTabIndices;
    if (features.isNotEmpty && !features.contains(_index)) {
      _index = features.first;
    }
  }

  int get _navIndex {
    final i = _featureTabIndices.indexOf(_index);
    return i < 0 ? 0 : i;
  }

  Object? _stepDestination(int delta) {
    final count = _featureTabIndices.length;
    if (count < 2) return null;
    final next = (_navIndex + delta) % count;
    _onNavSelected(next < 0 ? next + count : next);
    return null;
  }

  void _onNavSelected(int navIndex) {
    final fullIndex = _featureTabIndices[navIndex];
    if (fullIndex == _index) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _index = fullIndex);

    final telemetry = widget.telemetryService;
    if (telemetry != null) {
      unawaited(
        telemetry.logEvent('tab_open', detail: _kTabMeta[fullIndex].label),
      );
    }
  }

  void _onRoleChanged() {
    _clampIndex();
    setState(() {});
  }

  void _onBorrowChanged() {
    setState(() {});
  }

  Future<void> _openSignIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SignInScreen(
          authService: widget.authService,
          userRoleController: widget.userRoleController,
        ),
      ),
    );
  }

  List<NavigationDestination> _buildDestinations() {
    final overdueCount = widget.borrowController.overdueCount;
    return _featureTabIndices.map((i) {
      final m = _kTabMeta[i];
      final showBadge = i == AppTabs.borrowed && overdueCount > 0;
      Widget withBadge(Icon icon) => showBadge
          ? Semantics(
              label:
                  '$overdueCount overdue ${overdueCount == 1 ? 'loan' : 'loans'}',
              child: Badge(label: Text('$overdueCount'), child: icon),
            )
          : icon;
      return NavigationDestination(
        icon: withBadge(Icon(m.icon)),
        selectedIcon: withBadge(Icon(m.selectedIcon)),
        label: m.label,
      );
    }).toList();
  }

  void _openSecondary(int fullIndex) {
    final telemetry = widget.telemetryService;
    if (telemetry != null) {
      unawaited(
        telemetry.logEvent('tab_open', detail: _kTabMeta[fullIndex].label),
      );
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_kTabMeta[fullIndex].label)),
          body: _secondaryBody(fullIndex),
        ),
      ),
    );
  }

  Widget _secondaryBody(int fullIndex) {
    switch (fullIndex) {
      case 5:
        return DocsTab(roles: widget.userRoleController.roles);
      case 6:
        return UserManagementBody(roleController: widget.userRoleController);
      default:
        return SettingsTab(
          themeController: widget.themeController,
          userRoleController: widget.userRoleController,
          authService: widget.authService,
          issueReportService: widget.issueReportService,
          telemetryService: widget.telemetryService,
        );
    }
  }

  Widget _featureBody(int fullIndex) {
    switch (fullIndex) {
      case AppTabs.inventory:
        return InventoryTab(controller: widget.inventoryController);
      case AppTabs.packing:
        return PackingTab(
          controller: widget.packingController,
          inventoryController: widget.inventoryController,
          photoService: widget.photoService,
          containerPhotoSyncService: widget.containerPhotoSyncService,
        );
      case AppTabs.borrowed:
        return BorrowTab(controller: widget.borrowController);
      case AppTabs.maps:
        return MapsTab(
          controller: widget.mapLocationController,
          inventoryController: widget.inventoryController,
          imageStore: widget.mapImageStore,
        );
      default:
        return ScheduleTab(
          controller: widget.pitShiftController,
          authService: widget.authService,
          roleController: widget.userRoleController,
        );
    }
  }

  List<Widget> _buildAppBarActions() {
    final secondary = _secondaryTabIndices;
    return [
      IconButton(
        onPressed: _openSignIn,
        tooltip: 'Account',
        icon: const Icon(Icons.account_circle_outlined),
      ),
      if (secondary.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: _openSecondary,
          itemBuilder: (context) => [
            for (final i in secondary)
              PopupMenuItem<int>(
                value: i,
                child: Row(
                  children: [
                    Icon(_kTabMeta[i].icon, size: 20),
                    const SizedBox(width: 12),
                    Text(_kTabMeta[i].label),
                  ],
                ),
              ),
          ],
        ),
    ];
  }

  Widget _buildTitle(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: PitPalette.accentOf(context),
            shape: BoxShape.rectangle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Spectrum Pit',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }

  String _noAccessMessage() {
    final user = widget.authService.currentUser;
    if (user == null) return 'Sign in to continue.';
    final account = (user.email?.isNotEmpty ?? false)
        ? user.email!
        : user.displayName;
    return account.isEmpty
        ? 'Ask an admin to approve your account.'
        : 'Ask an admin to approve your account ($account).';
  }

  @override
  Widget build(BuildContext context) {
    final features = _featureTabIndices;

    if (features.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _buildTitle(context),
          actions: [
            IconButton(
              onPressed: _openSignIn,
              tooltip: 'Account',
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                'You do not have access.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _noAccessMessage(),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),

              if (widget.authService.currentUser == null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _openSignIn,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Sign in with Google'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final tabs = [for (final i in features) _featureBody(i)];

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.bracketRight, control: true):
            const _NextDestinationIntent(),
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
            const _NextDestinationIntent(),
        const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true):
            const _PreviousDestinationIntent(),
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            const _PreviousDestinationIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NextDestinationIntent: CallbackAction<_NextDestinationIntent>(
            onInvoke: (_) => _stepDestination(1),
          ),
          _PreviousDestinationIntent:
              CallbackAction<_PreviousDestinationIntent>(
                onInvoke: (_) => _stepDestination(-1),
              ),
        },

        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: _buildTitle(context),
              actions: _buildAppBarActions(),
            ),
            body: IndexedStack(index: _navIndex, children: tabs),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _navIndex,
              onDestinationSelected: _onNavSelected,
              destinations: _buildDestinations(),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextDestinationIntent extends Intent {
  const _NextDestinationIntent();
}

class _PreviousDestinationIntent extends Intent {
  const _PreviousDestinationIntent();
}
