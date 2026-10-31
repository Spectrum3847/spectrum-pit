import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';

import '../services/container_photo_sync_service.dart';
import '../services/event_match_schedule.dart';
import '../services/issue_report_service.dart';
import '../services/map_image_store.dart';
import '../services/photo_service.dart';
import '../services/spectrum_auth_service.dart';
import '../services/telemetry_service.dart';
import '../services/tour_service.dart';
import '../services/usage_rollup_service.dart';
import '../state/borrow_controller.dart';
import '../state/inventory_controller.dart';
import '../state/map_location_controller.dart';
import '../state/packing_controller.dart';
import '../state/pit_shift_controller.dart';
import '../state/robot_logs_controller.dart';
import '../state/active_event_controller.dart';
import '../state/scout_shift_mirror_controller.dart';
import '../state/theme_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/pit_palette.dart';
import '../models/user_role.dart';
import 'borrow_tab.dart';
import 'docs_viewer_screen.dart';
import 'glass_chrome.dart';
import 'item_jump_dialog.dart';
import 'now_tab.dart';
import 'inventory_tab.dart';
import 'maps_tab.dart';
import 'packing_tab.dart';
import 'robot_logs_tab.dart';
import 'event_picker_sheet.dart';
import 'schedule_tab.dart';
import 'settings_tab.dart';
import 'usage_tab.dart';
import 'sign_in_screen.dart';
import 'user_management_screen.dart';
import 'welcome_tour.dart';
import '../widgets/glass_modal.dart';

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
    required this.scoutShiftMirrorController,
    this.issueReportService,
    this.telemetryService,
    this.usageRollupService,
    this.debugLiquidGlassSupported,
    this.eventMatchLoader,
    this.tourService,
    this.robotLogsController,
    this.activeEventController,
    this.loadEvents,
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
  final ScoutShiftMirrorController scoutShiftMirrorController;
  final IssueReportService? issueReportService;
  final TelemetryService? telemetryService;

  final EventMatchLoader? eventMatchLoader;

  final TourService? tourService;

  final RobotLogsController? robotLogsController;

  final ActiveEventController? activeEventController;
  final EventsLoader? loadEvents;

  final UsageRollupService? usageRollupService;

  @visibleForTesting
  final bool? debugLiquidGlassSupported;

  @override
  State<AppShell> createState() => _AppShellState();
}

const _kSecondaryOrder = [
  AppTabs.docs,
  AppTabs.users,
  AppTabs.usage,
  AppTabs.robotLogs,
  AppTabs.settings,
];

const _kRailMinWidth = 600.0;
const _kSidebarMinWidth = 1024.0;

const _kRailWidth = 80.0;
const _kSidebarWidth = 256.0;

const _kBarTabLimit = 4;

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
  (
    label: 'Usage',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
  ),
  (label: 'Now', icon: Icons.home_outlined, selectedIcon: Icons.home_rounded),
  (
    label: 'Robot logs',
    icon: Icons.sd_storage_outlined,
    selectedIcon: Icons.sd_storage_rounded,
  ),
];

class _AppShellState extends State<AppShell> {
  int _index = AppTabs.now;

  final GlobalKey _tabStackKey = GlobalKey();

  final GlobalKey _navKey = GlobalKey();

  bool _tourVisible = false;
  bool _tourCheckPending = false;

  int? _tourReturnIndex;

  final InventorySearchRequest _inventorySearch = InventorySearchRequest();

  final Set<int> _visited = <int>{};
  final Map<int, Widget> _tabCache = <int, Widget>{};

  Timer? _minuteTick;

  bool _glassSupported = false;

  bool get _useGlass => _glassSupported && widget.themeController.liquidGlass;

  @override
  void initState() {
    super.initState();
    widget.userRoleController.addListener(_onRoleChanged);
    widget.borrowController.addListener(_onBorrowChanged);
    widget.themeController.addListener(_onThemeChanged);
    _minuteTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _clampIndex();
    _maybeShowTour();
    final override = widget.debugLiquidGlassSupported;
    if (override != null) {
      _glassSupported = override;
    } else {
      spectrumGlassSupported().then((value) {
        if (mounted) setState(() => _glassSupported = value);
      });
    }
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tabCache.clear();
  }

  @override
  void dispose() {
    widget.userRoleController.removeListener(_onRoleChanged);
    widget.borrowController.removeListener(_onBorrowChanged);
    widget.themeController.removeListener(_onThemeChanged);
    _minuteTick?.cancel();
    _inventorySearch.dispose();
    super.dispose();
  }

  List<int> get _visibleTabIndices => [
    for (final i in widget.userRoleController.visibleTabIndices)
      if (i != AppTabs.robotLogs || widget.robotLogsController != null) i,
  ];

  List<int> _orderedTabs() {
    final visible = _visibleTabIndices;
    final primary = widget.userRoleController.primaryTabIndices;
    assert(
      visible.every((i) => primary.contains(i) || _kSecondaryOrder.contains(i)),
      'a visible tab is in neither primaryTabIndices nor _kSecondaryOrder '
      'and would drop out of navigation',
    );
    return [...primary, ..._kSecondaryOrder.where(visible.contains)];
  }

  void _clampIndex() {
    final ordered = _orderedTabs();
    if (ordered.isNotEmpty && !ordered.contains(_index)) {
      _index = ordered.first;
    }
  }

  Object? _stepDestination(int delta) {
    final ordered = _orderedTabs();
    if (ordered.length < 2) return null;
    final current = ordered.indexOf(_index);
    _onTabSelected(ordered[(current + delta) % ordered.length]);
    return null;
  }

  void _onTabSelected(int fullIndex) {
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
    setState(() {
      _tabCache.clear();
      _visited.retainAll(_visibleTabIndices);

      if (_visited.isEmpty) _inventorySearch.request('');

      if (_visibleTabIndices.isEmpty) {
        _tourVisible = false;
        _tourReturnIndex = null;
      }
    });
    _maybeShowTour();
  }

  Future<void> _maybeShowTour() async {
    final tour = widget.tourService;
    if (tour == null || _tourVisible || _tourCheckPending) return;
    if (_visibleTabIndices.isEmpty) return;
    _tourCheckPending = true;
    try {
      final seen = await tour.isSeen();
      if (!mounted || seen || _visibleTabIndices.isEmpty) return;
      setState(() {
        _tourReturnIndex = _index;
        _tourVisible = true;
      });
    } finally {
      _tourCheckPending = false;
    }
  }

  void _dismissTour() {
    setState(() {
      _tourVisible = false;
      final back = _tourReturnIndex;
      if (back != null && _orderedTabs().contains(back)) _index = back;
      _tourReturnIndex = null;
    });

    widget.tourService?.markSeen();
  }

  void _replayTour() {
    final ordered = _orderedTabs();
    if (ordered.isEmpty) return;
    setState(() {
      _tourReturnIndex = _index;
      _index = ordered.first;
      _tourVisible = true;
    });
  }

  void _onTourStepChanged(TourStep step) {
    final tabIndex = step.tabIndex;
    if (tabIndex == null || tabIndex == _index) return;
    if (!_visibleTabIndices.contains(tabIndex)) return;
    setState(() => _index = tabIndex);
  }

  void _onBorrowChanged() {
    setState(() {});
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
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

  Future<void> _openItemJump(BuildContext dialogContext) async {
    final item = await showItemJump(
      dialogContext,
      controller: widget.inventoryController,
    );
    if (item == null || !mounted) return;
    _inventorySearch.request(item.name);
    _onTabSelected(AppTabs.inventory);
  }

  Widget _tabFor(int fullIndex) {
    if (!_visited.contains(fullIndex)) return const SizedBox.shrink();

    if (fullIndex == AppTabs.now) return _buildTab(fullIndex);
    return _tabCache[fullIndex] ??= _buildTab(fullIndex);
  }

  Widget _buildTab(int fullIndex) {
    switch (fullIndex) {
      case AppTabs.now:
        final visible = _visibleTabIndices;
        return Builder(
          builder: (context) => NowTab(
            inventoryController: widget.inventoryController,
            packingController: widget.packingController,
            borrowController: widget.borrowController,
            pitShiftController: widget.pitShiftController,
            currentUid: widget.userRoleController.currentUid,
            onOpenPacking: () => _onTabSelected(AppTabs.packing),
            onOpenBorrowed: () => _onTabSelected(AppTabs.borrowed),
            onOpenSchedule: () => _onTabSelected(AppTabs.schedule),
            onJump: visible.contains(AppTabs.inventory)
                ? () => unawaited(_openItemJump(context))
                : null,
          ),
        );
      case AppTabs.inventory:
        return InventoryTab(
          controller: widget.inventoryController,
          searchRequest: _inventorySearch,
        );
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
      case AppTabs.schedule:
        return ScheduleTab(
          controller: widget.pitShiftController,
          scoutShiftController: widget.scoutShiftMirrorController,
          authService: widget.authService,
          roleController: widget.userRoleController,
          eventMatchLoader: widget.eventMatchLoader,
          activeEventController: widget.activeEventController,
          loadEvents: widget.loadEvents,
        );
      case AppTabs.docs:
        return DocsTab(roles: widget.userRoleController.roles);
      case AppTabs.users:
        return UserManagementBody(roleController: widget.userRoleController);
      case AppTabs.usage:
        return UsageTab(
          service: widget.usageRollupService ?? FirestoreUsageRollupService(),
        );
      case AppTabs.robotLogs:
        return RobotLogsTab(controller: widget.robotLogsController!);
      default:
        return SettingsTab(
          themeController: widget.themeController,
          userRoleController: widget.userRoleController,
          authService: widget.authService,
          issueReportService: widget.issueReportService,
          telemetryService: widget.telemetryService,
          photoService: widget.photoService,
          onReplayTour: widget.tourService != null ? _replayTour : null,
        );
    }
  }

  Widget _tabIcon(int fullIndex, {required bool selected}) {
    final meta = _kTabMeta[fullIndex];
    final icon = Icon(selected ? meta.selectedIcon : meta.icon);
    final overdue = fullIndex == AppTabs.borrowed
        ? widget.borrowController.overdueCount
        : 0;
    if (overdue == 0) return icon;
    return Semantics(
      label: '$overdue overdue ${overdue == 1 ? 'loan' : 'loans'}',
      child: Badge(label: Text('$overdue'), child: icon),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      if (_visibleTabIndices.contains(AppTabs.inventory))
        Builder(
          builder: (context) => IconButton(
            onPressed: () => unawaited(_openItemJump(context)),
            tooltip: 'Find a tool',
            icon: const Icon(Icons.search_rounded),
          ),
        ),
      IconButton(
        onPressed: _openSignIn,
        tooltip: 'Account',
        icon: const Icon(Icons.account_circle_outlined),
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
        ? 'Ask an admin to set your roles from the Users tab.'
        : 'Ask an admin to set your roles from the Users tab ($account).';
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _orderedTabs();

    if (ordered.isEmpty) {
      return Scaffold(
        appBar: AppBar(
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

    _visited.add(_index);
    final width = MediaQuery.sizeOf(context).width;

    final hasNav = ordered.length >= 2;
    final useRail = hasNav && width >= _kRailMinWidth;

    Widget body = IndexedStack(
      key: _tabStackKey,
      index: ordered.indexOf(_index),
      children: [
        for (final i in ordered)
          _HoldLayoutWhileHidden(
            key: ValueKey(i),
            hidden: i != _index,
            child: _tabFor(i),
          ),
      ],
    );
    if (useRail) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: PitPalette.outlineOf(context)),
              ),
            ),
            child: _buildRail(ordered, sidebar: width >= _kSidebarMinWidth),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              child: body,
            ),
          ),
        ],
      );
    }

    final canJump = _visibleTabIndices.contains(AppTabs.inventory);
    final scaffold = Scaffold(
      appBar: AppBar(
        title: _buildTitle(context),
        actions: _buildAppBarActions(),
      ),
      body: body,
      bottomNavigationBar: hasNav && !useRail ? _buildBottomBar(ordered) : null,
    );

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
        if (_tourVisible)
          const SingleActivator(LogicalKeyboardKey.escape):
              const _DismissTourIntent(),
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
          _DismissTourIntent: CallbackAction<_DismissTourIntent>(
            onInvoke: (_) {
              _dismissTour();
              return null;
            },
          ),
        },

        child: Focus(
          autofocus: true,

          child: GlassChrome(
            enabled: _useGlass,
            child: Stack(
              children: [
                canJump
                    ? ItemJumpShortcut(
                        onJump: (context) => unawaited(_openItemJump(context)),
                        child: scaffold,
                      )
                    : scaffold,
                if (_tourVisible)
                  WelcomeTourOverlay(
                    steps: buildTourSteps(ordered),
                    navKey: hasNav ? _navKey : null,
                    onDone: _dismissTour,
                    onStepChanged: _onTourStepChanged,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(List<int> ordered) {
    final primary = widget.userRoleController.primaryTabIndices;
    final barTabs = (primary.isEmpty ? ordered : primary)
        .take(_kBarTabLimit)
        .toList();
    final moreTabs = ordered.where((i) => !barTabs.contains(i)).toList();
    final active = barTabs.indexOf(_index);
    return Builder(
      builder: (barContext) => NavigationBar(
        key: _navKey,

        selectedIndex: active >= 0 ? active : barTabs.length,
        onDestinationSelected: (i) {
          if (i < barTabs.length) {
            _onTabSelected(barTabs[i]);
          } else {
            unawaited(_showMoreTabs(barContext, moreTabs));
          }
        },
        destinations: [
          for (final i in barTabs)
            NavigationDestination(
              icon: _tabIcon(i, selected: false),
              selectedIcon: _tabIcon(i, selected: true),
              label: _kTabMeta[i].label,
            ),
          if (moreTabs.isNotEmpty)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded),
              label: 'More',
            ),
        ],
      ),
    );
  }

  Widget _buildRail(List<int> ordered, {required bool sidebar}) {
    final theme = widget.themeController;
    final extended = sidebar && theme.sidebarExpanded;
    final active = ordered.indexOf(_index);
    return NavigationRail(
      key: _navKey,
      minWidth: _kRailWidth,
      minExtendedWidth: _kSidebarWidth,
      leading: sidebar
          ? _SidebarToggle(
              expanded: extended,
              onPressed: () => unawaited(theme.setSidebarExpanded(!extended)),
            )
          : null,
      extended: extended,

      labelType: extended ? null : NavigationRailLabelType.all,

      scrollable: true,
      selectedIndex: active >= 0 ? active : null,
      onDestinationSelected: (i) => _onTabSelected(ordered[i]),
      destinations: [
        for (final i in ordered)
          NavigationRailDestination(
            icon: _tabIcon(i, selected: false),
            selectedIcon: _tabIcon(i, selected: true),
            label: Text(_kTabMeta[i].label),
          ),
      ],
    );
  }

  Future<void> _showMoreTabs(BuildContext barContext, List<int> tabs) {
    return showGlassModalBottomSheet<void>(
      context: barContext,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final i in tabs)
              ListTile(
                selected: i == _index,
                leading: _tabIcon(i, selected: i == _index),
                title: Text(_kTabMeta[i].label),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _onTabSelected(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarToggle extends StatelessWidget {
  const _SidebarToggle({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final animation = NavigationRail.extendedAnimation(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => SizedBox(
        width: _kRailWidth + (_kSidebarWidth - _kRailWidth) * animation.value,
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: (_kRailWidth - 48) / 2),
        child: IconButton(
          tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
          icon: Icon(expanded ? Icons.menu_open : Icons.menu),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _HoldLayoutWhileHidden extends SingleChildRenderObjectWidget {
  const _HoldLayoutWhileHidden({
    required this.hidden,
    required super.child,
    super.key,
  });

  final bool hidden;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHoldLayoutWhileHidden(hidden);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHoldLayoutWhileHidden renderObject,
  ) {
    renderObject.hidden = hidden;
  }
}

class _RenderHoldLayoutWhileHidden extends RenderProxyBox {
  _RenderHoldLayoutWhileHidden(this._hidden);

  bool _hidden;
  set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    markNeedsLayout();
  }

  BoxConstraints? _held;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    if (!_hidden || _held == null) _held = constraints;
    child.layout(_held!, parentUsesSize: true);
    size = constraints.constrain(child.size);
  }
}

class _NextDestinationIntent extends Intent {
  const _NextDestinationIntent();
}

class _DismissTourIntent extends Intent {
  const _DismissTourIntent();
}

class _PreviousDestinationIntent extends Intent {
  const _PreviousDestinationIntent();
}
