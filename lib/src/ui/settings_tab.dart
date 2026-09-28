import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../services/android_update_service.dart';
import '../services/debug_info.dart';
import '../services/desktop_launcher_service.dart';
import '../services/desktop_self_update_service.dart';
import '../services/desktop_update_service.dart';
import '../models/user_role.dart';
import 'about_screen.dart';
import '../services/issue_report_service.dart';
import '../services/photo_service.dart';
import '../services/spectrum_auth_service.dart';
import '../services/telemetry_service.dart';
import '../services/web_cache_reset.dart';
import '../services/web_channel_service.dart';
import '../theme/pit_palette.dart';
import '../state/theme_controller.dart';
import '../state/user_role_controller.dart';
import 'glass_chrome.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    required this.themeController,
    required this.userRoleController,
    required this.authService,
    this.issueReportService,
    this.telemetryService,
    this.photoService,
    super.key,
  });

  final ThemeController themeController;
  final UserRoleController userRoleController;
  final SpectrumAuthService authService;

  final IssueReportService? issueReportService;

  final TelemetryService? telemetryService;

  final PhotoService? photoService;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final IssueReportService _reportService =
      widget.issueReportService ?? IssueReportService();

  ThemeController get _themeCtrl => widget.themeController;
  UserRoleController get _roleCtrl => widget.userRoleController;

  String _rolesLabel() {
    final roles = _roleCtrl.roles.map((r) => r.displayName).toList()..sort();
    return roles.join(', ');
  }

  bool get _canReport =>
      widget.authService.currentUser != null && _roleCtrl.roles.isMember;

  static const List<String> _reportAreas = [
    'Inventory (tool locations, lab/pit maps)',
    'Event packing (Packing/Staging/Loading/Ready)',
    'Borrowed tools tracker',
    'Lab and pit maps',
    'Pit team scheduling',
    'Roles / permissions',
    'Firebase sync',
    'Auth / sign-in',
    'Web build / offline support',
    'Build, CI, or release tooling',
    'Docs',
    'Other',
    'Not sure',
  ];

  static const List<String> _reportImpacts = [
    'Blocks work completely',
    'Major degradation or frequent failure',
    'Minor bug or occasional failure',
    'Cosmetic issue',
  ];

  Future<void> _reportProblem() async {
    final user = widget.authService.currentUser;
    if (user == null) return;

    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final bodyFocus = FocusNode();
    var kind = 'bug';
    String? area;
    String? impact;
    final screenshots = <PickedPhoto>[];
    final photoService = widget.photoService;
    final canAttach =
        photoService != null && _reportService.supportsScreenshots;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Report a problem'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your name and device details are attached automatically '
                    'to help us debug.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'bug', label: Text('Bug')),
                      ButtonSegment(value: 'feedback', label: Text('Feedback')),
                    ],
                    selected: {kind},
                    onSelectionChanged: (selection) =>
                        setDialogState(() => kind = selection.first),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: area,
                    decoration: const InputDecoration(
                      labelText: 'Area',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final option in _reportAreas)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) => setDialogState(() => area = value),
                  ),
                  if (kind == 'bug') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: impact,
                      decoration: const InputDecoration(
                        labelText: 'Impact',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final option in _reportImpacts)
                          DropdownMenuItem(value: option, child: Text(option)),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => impact = value),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Summary',
                      hintText: 'Something did not work',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    focusNode: bodyFocus,
                    maxLines: 5,
                    maxLength: 4096,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: kind == 'feedback'
                          ? 'Your feedback'
                          : 'What happened',
                      hintText: kind == 'feedback'
                          ? 'What would you like to see?'
                          : 'Steps to reproduce, what you expected, etc.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (canAttach) ...[
                    const SizedBox(height: 8),
                    _ScreenshotPicker(
                      photoService: photoService,
                      screenshots: screenshots,
                      onChanged: () => setDialogState(() {}),
                      onError: (message) =>
                          _showReportSnack(message, isError: true),

                      onPickComplete: kIsWeb
                          ? () => WidgetsBinding.instance.addPostFrameCallback((
                              _,
                            ) {
                              if (ctx.mounted) bodyFocus.requestFocus();
                            })
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    titleCtrl.dispose();
    bodyCtrl.dispose();
    bodyFocus.dispose();
    if (submitted != true) return;
    if (title.isEmpty) {
      _showReportSnack('Add a short summary before sending.', isError: true);
      return;
    }
    try {
      final dropped = await _reportService.submit(
        title: title,
        body: body,
        reporterUid: user.uid,
        reporterName: user.displayName.isNotEmpty
            ? user.displayName
            : 'Unknown',
        roles: _rolesLabel(),
        kind: kind,
        area: area ?? '',
        impact: kind == 'bug' ? (impact ?? '') : '',
        screenshots: screenshots,
      );
      _showReportSnack(
        dropped == 0
            ? 'Report sent. Thank you.'
            : 'Report sent, but $dropped screenshot'
                  '${dropped == 1 ? '' : 's'} could not be attached.',
      );
    } catch (e) {
      debugPrint('Bug report submit failed: $e');
      _showReportSnack(
        'Could not send the report. Please try again.',
        isError: true,
      );
    }
  }

  void _showReportSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_themeCtrl, _roleCtrl]),
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    for (final mode in ThemeMode.values)
                      ButtonSegment<ThemeMode>(
                        value: mode,
                        label: Text(_themeModeLabel(mode)),
                        icon: Icon(_themeModeIcon(mode)),
                      ),
                  ],
                  selected: {_themeCtrl.themeMode},
                  onSelectionChanged: (s) => _themeCtrl.setThemeMode(s.first),
                ),
              ),
            ),
            _LiquidGlassTile(controller: _themeCtrl),
            if (_canReport) ...[
              const SizedBox(height: 24),
              Text('Help', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Hit a bug or have feedback? Send a report to the '
                          'app team. Your device details are attached to help '
                          'us debug.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _reportProblem,
                        icon: const Icon(Icons.bug_report_outlined, size: 18),
                        label: const Text('Report a problem'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text('About', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'App version, build, and device details. These are the same '
              'details attached to a problem report, so you can read them off '
              'here when asking for help.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About Spectrum Pit'),
                subtitle: const Text(
                  'Credits, open source licenses, and links',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _TelemetryTile(service: widget.telemetryService),
            const SizedBox(height: 12),
            const _DebugInfoCard(),
            if (kIsWeb) ...[
              const SizedBox(height: 12),
              const _WebChannelTile(),
              const SizedBox(height: 12),
              const _ClearWebCacheTile(),
            ],
            if (_isDesktopPlatform) ...[
              const SizedBox(height: 12),
              const _LauncherTile(),
              const SizedBox(height: 12),
              const _DesktopUpdateTile(),
            ],
            if (_isAndroidPlatform) ...[
              const SizedBox(height: 12),
              const _AndroidUpdateTile(),
            ],
          ],
        );
      },
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

bool get _isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class _LauncherTile extends StatefulWidget {
  const _LauncherTile();

  @override
  State<_LauncherTile> createState() => _LauncherTileState();
}

class _LauncherTileState extends State<_LauncherTile> {
  final DesktopLauncherService _service = DesktopLauncherService();
  bool _working = false;
  String? _status;

  Future<void> _register() async {
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      await _service.registerInLauncher();
      if (!mounted) return;
      setState(() => _status = 'Added to your applications menu.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not add it to the menu.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Applications menu',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Add Spectrum Pit to your desktop applications menu so it '
              'shows up in search. Run this once after downloading a new build.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _register,
                icon: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.apps_rounded, size: 18),
                label: const Text('Add to applications menu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebChannelTile extends StatefulWidget {
  const _WebChannelTile();

  @override
  State<_WebChannelTile> createState() => _WebChannelTileState();
}

class _WebChannelTileState extends State<_WebChannelTile> {
  final WebChannelService _service = WebChannelService();
  bool _switching = false;
  String? _status;

  WebChannel? get _current => WebChannelService.channelForHost(Uri.base.host);

  Future<void> _switchTo(WebChannel channel) async {
    if (_switching || channel == _current) return;
    setState(() {
      _switching = true;
      _status = 'Checking the ${channel.label.toLowerCase()} site...';
    });
    final available = await _service.hasPublishedBuild(channel);
    if (!mounted) return;
    if (!available) {
      setState(() {
        _switching = false;
        _status =
            'The ${channel.label.toLowerCase()} site has no build '
            'published yet.';
      });
      return;
    }
    setState(
      () => _status = 'Opening the ${channel.label.toLowerCase()} site...',
    );
    final launched = await launchUrl(channel.url, webOnlyWindowName: '_self');
    if (!mounted) return;
    setState(() {
      _switching = false;
      if (!launched) {
        _status =
            'Could not open the ${channel.label.toLowerCase()} site. '
            'Try again, or navigate to it directly.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Web channel', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Stable follows published releases; staging follows every '
              'change as it lands. Switching opens the other site.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<WebChannel>(
              segments: [
                for (final channel in WebChannel.values)
                  ButtonSegment(value: channel, label: Text(channel.label)),
              ],
              selected: {?current},
              emptySelectionAllowed: current == null,
              onSelectionChanged: _switching ? null : (s) => _switchTo(s.first),
              showSelectedIcon: false,
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          ],
        ),
      ),
    );
  }
}

class _ClearWebCacheTile extends StatefulWidget {
  const _ClearWebCacheTile();

  @override
  State<_ClearWebCacheTile> createState() => _ClearWebCacheTileState();
}

class _ClearWebCacheTileState extends State<_ClearWebCacheTile> {
  bool _clearing = false;
  String? _status;

  Future<void> _clear() async {
    setState(() {
      _clearing = true;
      _status = null;
    });
    try {
      await clearCachedBuild();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _status = 'Could not clear the cache: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Clear cache', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Web keeps this build offline-ready in the browser, which can '
              'show an old build after a deploy. Clear it and reload to '
              'force this tab to fetch the current one.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _clearing ? null : _clear,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_clearing ? 'Clearing...' : 'Clear cache and reload'),
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          ],
        ),
      ),
    );
  }
}

class _DesktopUpdateTile extends StatefulWidget {
  const _DesktopUpdateTile();

  @override
  State<_DesktopUpdateTile> createState() => _DesktopUpdateTileState();
}

class _DesktopUpdateTileState extends State<_DesktopUpdateTile> {
  final DesktopUpdateService _service = DesktopUpdateService();
  final DesktopSelfUpdateService _selfUpdate = DesktopSelfUpdateService();
  bool _checking = false;
  bool _installing = false;
  String? _status;
  DesktopUpdateInfo? _update;
  DesktopUpdateChannel _channel = DesktopUpdateChannel.stable;
  bool _autoUpdate = false;

  @override
  void initState() {
    super.initState();
    _service
        .currentChannel()
        .then((channel) {
          if (mounted) setState(() => _channel = channel);
        })
        .catchError((Object error) {
          debugPrint('Update channel read failed: $error');
        });
    _service
        .autoUpdateEnabled()
        .then((enabled) {
          if (mounted) setState(() => _autoUpdate = enabled);
        })
        .catchError((Object error) {
          debugPrint('Auto-update setting read failed: $error');
        });
  }

  Future<void> _setAutoUpdate(bool enabled) async {
    setState(() => _autoUpdate = enabled);
    await _service.setAutoUpdateEnabled(enabled);
  }

  bool get _canInstall =>
      _update?.assetUrl != null && _selfUpdate.canSelfUpdate;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      final channel = await _service.currentChannel();
      final result = await _service.checkForUpdate(channel: channel);
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _applyResult(result, channel);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not check for updates right now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _switchChannel(DesktopUpdateChannel channel) async {
    setState(() {
      _channel = channel;
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      await _service.setChannel(channel);
      final result = await _service.checkForUpdate(
        channel: channel,
        ignoreVersionGate: true,
      );
      if (!mounted) return;
      setState(() => _applyResult(result, channel));
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not check for updates right now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _applyResult(DesktopUpdateCheck result, DesktopUpdateChannel channel) {
    _update = result.update;
    if (result.update != null) {
      _status = 'Update available: ${result.update!.latestVersion}.';
    } else if (result.hasRelease) {
      _status = 'You are on the latest version.';
    } else {
      _status =
          'No ${channel.name} build has been published yet, so there is '
          'nothing to update to.';
    }
  }

  Future<void> _openDownload() async {
    final info = _update;
    if (info == null) return;
    final launched = await launchUrl(
      info.releaseUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      setState(() => _status = 'Could not open the download page.');
    }
  }

  Future<void> _install() async {
    final info = _update;
    final url = info?.assetUrl;
    final digest = info?.expectedSha256;
    if (url == null) return;
    if (digest == null || digest.isEmpty) {
      setState(() {
        _status =
            'This release has no checksum, so it cannot be installed '
            'automatically. Opening the download page.';
      });
      await launchUrl(info!.releaseUrl, mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      _installing = true;
      _status = 'Downloading update...';
    });
    try {
      await _selfUpdate.update(Uri.parse(url), expectedSha256: digest);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _status = 'Could not install automatically; opening the download page.';
      });
      await launchUrl(info!.releaseUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Desktop updates',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Off by default: a launch can land mid-event, with unsaved '
              'data on screen. Turn this on to check for a newer release on '
              'launch and install it without asking, or leave it off and '
              'check and download by hand below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Check and install on launch'),
              value: _autoUpdate,
              onChanged: _setAutoUpdate,
            ),
            const SizedBox(height: 8),
            SegmentedButton<DesktopUpdateChannel>(
              segments: const [
                ButtonSegment(
                  value: DesktopUpdateChannel.stable,
                  label: Text('Stable'),
                ),
                ButtonSegment(
                  value: DesktopUpdateChannel.nightly,
                  label: Text('Nightly'),
                ),
              ],
              selected: {_channel},
              onSelectionChanged: (_checking || _installing)
                  ? null
                  : (s) => _switchChannel(s.first),
              showSelectedIcon: false,
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_update != null)
                  FilledButton.icon(
                    onPressed: _installing
                        ? null
                        : (_canInstall ? _install : _openDownload),
                    icon: _installing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_canInstall ? 'Install update' : 'Get update'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (_checking || _installing) ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check for updates'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AndroidUpdateTile extends StatefulWidget {
  const _AndroidUpdateTile();

  @override
  State<_AndroidUpdateTile> createState() => _AndroidUpdateTileState();
}

class _AndroidUpdateTileState extends State<_AndroidUpdateTile> {
  final AndroidUpdateService _service = AndroidUpdateService();
  bool _checking = false;
  bool _installing = false;
  String? _status;
  AndroidUpdateInfo? _update;
  DesktopUpdateChannel _channel = DesktopUpdateChannel.stable;

  @override
  void initState() {
    super.initState();
    _service
        .currentChannel()
        .then((channel) {
          if (mounted) setState(() => _channel = channel);
        })
        .catchError((Object error) {
          debugPrint('Update channel read failed: $error');
        });
  }

  bool get _canInstall =>
      _update?.apkUrl != null && (_update?.expectedSha256?.isNotEmpty ?? false);

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      final channel = await _service.currentChannel();
      final result = await _service.checkForUpdate(channel: channel);
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _applyResult(result, channel);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not check for updates right now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _switchChannel(DesktopUpdateChannel channel) async {
    setState(() {
      _channel = channel;
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      await _service.setChannel(channel);
      final result = await _service.checkForUpdate(
        channel: channel,
        ignoreVersionGate: true,
      );
      if (!mounted) return;
      setState(() => _applyResult(result, channel));
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not check for updates right now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _applyResult(AndroidUpdateCheck result, DesktopUpdateChannel channel) {
    _update = result.update;
    if (result.update != null) {
      _status = 'Update available: ${result.update!.latestVersion}.';
    } else if (result.hasRelease) {
      _status = 'You are on the latest version.';
    } else {
      _status =
          'No ${channel.name} build has been published yet, so there is '
          'nothing to update to.';
    }
  }

  Future<void> _openDownload() async {
    final info = _update;
    if (info == null) return;
    await launchUrl(info.releaseUrl, mode: LaunchMode.externalApplication);
  }

  Future<void> _install() async {
    final info = _update;
    if (info == null) return;
    if (!_canInstall) {
      setState(() {
        _status =
            'This release has no checksum, so it cannot be installed '
            'automatically. Opening the download page.';
      });
      await launchUrl(info.releaseUrl, mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      _installing = true;
      _status = 'Downloading update...';
    });
    try {
      final outcome = await _service.downloadAndInstall(info);
      if (!mounted) return;
      setState(() {
        _installing = false;
        _status = outcome == AndroidInstallOutcome.permissionRequired
            ? 'Allow installs from Spectrum Pit on the screen that just '
                  'opened, then tap Install again.'
            : 'Downloaded. Confirm the install prompt to finish.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _status = 'Could not install automatically; opening the download page.';
      });
      await launchUrl(info.releaseUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('App updates', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Sideloaded installs have no app store to update them. Check '
              'the public releases repo by hand below, or switch tracks to '
              'follow nightly builds instead of stable releases.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<DesktopUpdateChannel>(
              segments: const [
                ButtonSegment(
                  value: DesktopUpdateChannel.stable,
                  label: Text('Stable'),
                ),
                ButtonSegment(
                  value: DesktopUpdateChannel.nightly,
                  label: Text('Nightly'),
                ),
              ],
              selected: {_channel},
              onSelectionChanged: (_checking || _installing)
                  ? null
                  : (s) => _switchChannel(s.first),
              showSelectedIcon: false,
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_update != null)
                  FilledButton.icon(
                    onPressed: _installing
                        ? null
                        : (_canInstall ? _install : _openDownload),
                    icon: _installing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_canInstall ? 'Install update' : 'Get update'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (_checking || _installing) ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check for updates'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryTile extends StatefulWidget {
  const _TelemetryTile({this.service});

  final TelemetryService? service;

  @override
  State<_TelemetryTile> createState() => _TelemetryTileState();
}

class _TelemetryTileState extends State<_TelemetryTile> {
  late final TelemetryService _service = widget.service ?? TelemetryService();
  bool _enabled = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service
        .isEnabled()
        .then((value) {
          if (mounted) setState(() => _enabled = value);
        })
        .catchError((Object error) {
          debugPrint('Telemetry preference read failed: $error');
        });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    _busy = true;
    final previous = _enabled;
    setState(() => _enabled = value);
    try {
      await _service.setEnabled(value);
    } catch (error) {
      debugPrint('Telemetry preference write failed: $error');
      if (mounted) setState(() => _enabled = previous);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Usage data', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Share anonymous usage data (app version, platform, and which '
              'tabs get opened) to help improve the app. No personal '
              'information or account details are collected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share anonymous usage data'),
              value: _enabled,
              onChanged: _toggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugInfoCard extends StatefulWidget {
  const _DebugInfoCard();

  @override
  State<_DebugInfoCard> createState() => _DebugInfoCardState();
}

class _DebugInfoCardState extends State<_DebugInfoCard> {
  late final Future<DebugInfo> _info = DebugInfo.gather();

  Future<void> _copy(DebugInfo info) async {
    await Clipboard.setData(ClipboardData(text: info.toDisplayText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Debug info copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<DebugInfo>(
          future: _info,
          builder: (context, snapshot) {
            final info = snapshot.data;
            if (info == null) {
              return Text(
                'Loading build info...',
                style: Theme.of(context).textTheme.bodySmall,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(label: 'App version', value: info.versionLabel),
                _InfoRow(label: 'Commit', value: info.commitLabel),
                if (info.gitBranch.isNotEmpty)
                  _InfoRow(label: 'Branch', value: info.gitBranch),
                if (info.buildDate.isNotEmpty)
                  _InfoRow(label: 'Built', value: info.buildDate),
                _InfoRow(label: 'Platform', value: info.platform),
                if (info.osVersion.isNotEmpty)
                  _InfoRow(label: 'OS', value: info.osVersion),
                if (info.device.isNotEmpty)
                  _InfoRow(label: 'Device', value: info.device),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _copy(info),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScreenshotPicker extends StatelessWidget {
  const _ScreenshotPicker({
    required this.photoService,
    required this.screenshots,
    required this.onChanged,
    required this.onError,
    this.onPickComplete,
  });

  final PhotoService photoService;
  final List<PickedPhoto> screenshots;
  final VoidCallback onChanged;
  final void Function(String message) onError;

  final VoidCallback? onPickComplete;

  Future<void> _add() async {
    try {
      final picked = await photoService.pickImage();
      if (picked == null) return;

      if (picked.bytes.length > PhotoService.maxBytes) {
        onError('That image is over the 2 MB limit. Crop or shrink it.');
        return;
      }
      screenshots.add(picked);
      onChanged();
    } catch (e) {
      onError('Could not attach that image: $e');
    } finally {
      onPickComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = screenshots.length >= maxReportScreenshots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: OutlinedButton.icon(
                onPressed: full ? null : _add,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Attach screenshot'),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${screenshots.length} of $maxReportScreenshots',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (screenshots.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final shot in screenshots)
                _ScreenshotThumbnail(
                  bytes: shot.bytes,
                  onRemove: () {
                    screenshots.remove(shot);
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ScreenshotThumbnail extends StatelessWidget {
  const _ScreenshotThumbnail({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(PitPalette.radiusSm),
          child: Image.memory(
            bytes,
            width: 64,
            height: 64,
            fit: BoxFit.cover,

            errorBuilder: (context, error, stack) => Container(
              width: 64,
              height: 64,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined, size: 20),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: onRemove,
            icon: const Icon(Icons.cancel, size: 18),
          ),
        ),
      ],
    );
  }
}

class _LiquidGlassTile extends StatefulWidget {
  const _LiquidGlassTile({required this.controller});

  final ThemeController controller;

  @override
  State<_LiquidGlassTile> createState() => _LiquidGlassTileState();
}

class _LiquidGlassTileState extends State<_LiquidGlassTile> {
  bool? _supported;

  @override
  void initState() {
    super.initState();
    spectrumGlassSupported().then((value) {
      if (mounted) setState(() => _supported = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_supported != true) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isMacos = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Liquid Glass', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                isMacos
                    ? 'Beta. Draws $glassChromeSurfaces on Apple\'s Liquid '
                          'Glass material (macOS 26), with the content '
                          'behind them showing through. Off by default '
                          'while it is being tested.'
                    : 'Draws $glassChromeSurfaces on Apple\'s Liquid Glass '
                          'material (iOS 26, iPadOS 26), with the content '
                          'behind them showing through. On by default; turn '
                          'this off for the flat design instead.',
                style: theme.textTheme.bodySmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Liquid Glass chrome'),
                value: widget.controller.liquidGlass,
                onChanged: widget.controller.setLiquidGlass,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
