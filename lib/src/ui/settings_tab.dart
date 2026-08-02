import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../services/debug_info.dart';
import '../services/desktop_launcher_service.dart';
import '../services/desktop_self_update_service.dart';
import '../services/desktop_update_service.dart';
import '../models/user_role.dart';
import '../services/issue_report_service.dart';
import '../services/spectrum_auth_service.dart';
import '../services/telemetry_service.dart';
import '../state/theme_controller.dart';
import '../state/user_role_controller.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    required this.themeController,
    required this.userRoleController,
    required this.authService,
    this.issueReportService,
    this.telemetryService,
    super.key,
  });

  final ThemeController themeController;
  final UserRoleController userRoleController;
  final SpectrumAuthService authService;

  final IssueReportService? issueReportService;

  final TelemetryService? telemetryService;

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

  Future<void> _reportProblem() async {
    final user = widget.authService.currentUser;
    if (user == null) return;

    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a problem'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell us what went wrong. Your name and device details are '
                'attached automatically to help us debug.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
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
                maxLines: 5,
                maxLength: 4096,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What happened',
                  hintText: 'Steps to reproduce, what you expected, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
    );
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    titleCtrl.dispose();
    bodyCtrl.dispose();
    if (submitted != true) return;
    if (title.isEmpty) {
      _showReportSnack('Add a short summary before sending.', isError: true);
      return;
    }
    try {
      await _reportService.submit(
        title: title,
        body: body,
        reporterUid: user.uid,
        reporterName: user.displayName.isNotEmpty
            ? user.displayName
            : 'Unknown',
        roles: _rolesLabel(),
      );
      _showReportSnack('Report sent. Thank you.');
    } catch (e) {
      _showReportSnack('Could not send the report: $e', isError: true);
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
            _TelemetryTile(service: widget.telemetryService),
            const SizedBox(height: 12),
            const _DebugInfoCard(),
            if (_isDesktopPlatform) ...[
              const SizedBox(height: 12),
              const _LauncherTile(),
              const SizedBox(height: 12),
              const _DesktopUpdateTile(),
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

  bool get _canInstall =>
      _update?.appImageUrl != null && _selfUpdate.canSelfUpdate;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      final info = await _service.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = info;
        _status = info == null
            ? 'You are on the latest version.'
            : 'Update available: ${info.latestVersion}.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not check for updates right now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openDownload() async {
    final info = _update;
    if (info == null) return;
    await launchUrl(info.releaseUrl, mode: LaunchMode.externalApplication);
  }

  Future<void> _install() async {
    final info = _update;
    final url = info?.appImageUrl;
    if (url == null) return;
    setState(() {
      _installing = true;
      _status = 'Downloading update...';
    });
    try {
      await _selfUpdate.update(Uri.parse(url));
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
              'Desktop builds do not auto-update. Check for a newer release '
              'and download it when one is available.',
              style: Theme.of(context).textTheme.bodySmall,
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

  @override
  void initState() {
    super.initState();
    _service.isEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await _service.setEnabled(value);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug info copied')));
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
