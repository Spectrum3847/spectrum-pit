import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/robot_log_file.dart';
import '../services/robot_devices.dart';
import '../state/robot_logs_controller.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';

class RobotLogsTab extends StatefulWidget {
  const RobotLogsTab({required this.controller, super.key});

  final RobotLogsController controller;

  @override
  State<RobotLogsTab> createState() => _RobotLogsTabState();
}

class _RobotLogsTabState extends State<RobotLogsTab> {
  RobotLogsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.bootstrap().catchError((Object e) {
      if (mounted) _toast('Could not read the logs folder: $e');
    });
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _openSettings() async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _SettingsDialog(controller: _c),
    );
    if (message != null && mounted) _toast(message);
  }

  Future<void> _saveBuffers(List<ScannedLimelight> cameras) async {
    final failed = <String>[];
    for (final c in cameras) {
      try {
        await _c.saveRewindBuffer(c);
      } on Object catch (e) {
        failed.add('${c.limelight.name}: $e');
      }
    }
    if (!mounted) return;
    _toast(
      failed.isEmpty
          ? 'Cameras saved their last 165 s. Pull again to copy it.'
          : failed.join('\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _syncPanel(context),
              const SizedBox(height: 32),
              ..._matches(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncPanel(BuildContext context) {
    final theme = Theme.of(context);
    final muted = PitPalette.inkMutedOf(context);
    final job = _c.job;
    final working = _c.scanning || _c.busy;
    final cameras = _c.scan?.limelights ?? const <ScannedLimelight>[];
    return Material(
      color: PitPalette.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        side: BorderSide(color: PitPalette.outlineOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_statusIcon(), color: muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_statusText(), style: theme.textTheme.bodyLarge),
                ),
                IconButton(
                  tooltip: 'Robot logs settings',
                  onPressed: working ? null : _openSettings,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: working ? null : _c.syncAll,
                icon: working
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  working ? _workingText() : 'Pull and send everything new',
                ),
              ),
            ),
            if (_c.busy && job != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: job.total == 0
                    ? null
                    : (job.index + job.progress) / job.total,
              ),
            ],
            if (_c.uploadKey.isEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.key_rounded, size: 20, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Files are copied but not sent until the upload key is set.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    onPressed: working ? null : _openSettings,
                    child: const Text('Add key'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _c.autoSync,
              onChanged: (v) => _c.setAutoSync(v),
              title: const Text('Do it automatically'),
              subtitle: Text(
                'Checks every ${_c.autoInterval.inSeconds} s while Spectrum Pit '
                'is open, and pulls and sends as soon as the robot is plugged in.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
            if (cameras.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message:
                      'For a match where the robot code did not trigger a '
                      'capture',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    onPressed: working ? null : () => _saveBuffers(cameras),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Save last 165 s on the cameras'),
                  ),
                ),
              ),
            for (final e in [...?_c.scan?.errors, ...?job?.errors].take(4))
              _ErrorLine(text: e),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon() {
    final scan = _c.scan;
    if (scan == null) return Icons.cable_rounded;
    return scan.robots.isEmpty
        ? Icons.portable_wifi_off_rounded
        : Icons.memory_rounded;
  }

  String _statusText() {
    final scan = _c.scan;
    if (scan == null) {
      return 'Plug this laptop into the robot over Ethernet, stay on Wi-Fi '
          'for the internet, then pull.';
    }
    final cams = scan.limelights.length;
    final camText = cams == 0 ? 'no cameras' : _count(cams, 'camera');
    if (scan.robots.isEmpty) {
      return 'No robot found on ${_c.teams.map((t) => '${teamNet(t)}.x').join(' or ')}'
          '${cams == 0 ? '' : ', $camText'}. Checked ${_clock(scan.at)}.';
    }
    final robots = scan.robots.map((r) => 'Robot ${r.team}').join(' and ');
    return '$robots connected, $camText. Checked ${_clock(scan.at)}.';
  }

  String _workingText() {
    final job = _c.job;
    if (_c.scanning || job == null || job.done) return 'Looking for the robot';
    final verb = job.title == 'Copy' ? 'Copying' : 'Sending';
    return '$verb ${math.min(job.index + 1, job.total)} of ${job.total}';
  }

  List<Widget> _matches(BuildContext context) {
    final groups = _c.groups;
    final waiting = _c.newRemoteItems.length;
    return [
      Text('Matches', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        'Files are kept in ${_c.folder}. Open a match to rename a file or '
        'change its team before it is sent.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: PitPalette.inkMutedOf(context)),
      ),
      const SizedBox(height: 12),
      if (waiting > 0)
        _GroupRow(
          title: '${_count(waiting, 'file')} on the robot',
          detail: waiting == 1
              ? 'Pull to copy and send it.'
              : 'Pull to copy and send them.',
          chip: const _Chip.neutral(
            icon: Icons.download_rounded,
            label: 'Not copied',
          ),
        ),
      if (groups.isEmpty && waiting == 0)
        const _Slot(
          icon: Icons.folder_open_rounded,
          text: 'Nothing pulled yet. Plug in the robot and press Pull.',
        ),
      for (final g in groups) _group(context, g),
    ];
  }

  Widget _group(BuildContext context, LogGroup g) {
    final parts = [
      if (g.logCount > 0) _count(g.logCount, 'log'),
      if (g.rewindCount > 0) _count(g.rewindCount, 'rewind'),
    ].join(' + ');
    final when = g.recordedUnixMs == null
        ? ''
        : ' · ${_when(DateTime.fromMillisecondsSinceEpoch(g.recordedUnixMs!))}';
    final url = g.files
        .map(_c.matchUrl)
        .firstWhere((u) => u != null, orElse: () => null);
    return _GroupRow(
      title: g.title,
      detail: '$parts$when',
      chip: g.sent
          ? _Chip.ready(
              icon: Icons.cloud_done_outlined,
              label: 'Sent',
              onTap: url == null ? null : () => launchUrl(url),
              tooltip: 'Open this match on the log site',
            )
          : const _Chip.neutral(
              icon: Icons.cloud_upload_outlined,
              label: 'Not sent',
            ),
      children: [for (final f in g.files) _fileRow(context, f)],
    );
  }

  Widget _fileRow(BuildContext context, RobotLogFile f) {
    final muted = PitPalette.inkMutedOf(context);
    final detail = [
      if (f.team != null) 'Team ${f.team}',
      if (f.name != f.original) 'copied as ${f.original}',
      _size(f.size),
      f.isSent ? 'sent' : 'not sent',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 4, 0, 4),
      child: Row(
        children: [
          Icon(
            f.kind == RobotLogKind.wpilog
                ? Icons.description_outlined
                : Icons.videocam_outlined,
            size: 20,
            color: muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: f.name,
                    style: pitCodeStyle(
                      context,
                      color: PitPalette.inkOf(context),
                    ),
                  ),
                  const TextSpan(text: '\n'),
                  TextSpan(
                    text: detail,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Rename or change team',
            onPressed: _c.busy
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => _EditFileDialog(controller: _c, file: f),
                  ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

String _size(int bytes) {
  if (bytes < 1e6) return '${(bytes / 1e3).toStringAsFixed(0)} KB';
  return '${(bytes / 1e6).toStringAsFixed(bytes < 1e7 ? 1 : 0)} MB';
}

String _clock(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
}

String _when(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${_clock(l)}';
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.title,
    required this.detail,
    required this.chip,
    this.children = const [],
  });

  final String title;
  final String detail;
  final Widget chip;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final subtitle = Text(
      detail,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
    );
    final head = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
              subtitle,
            ],
          ),
        ),
        const SizedBox(width: 12),
        chip,
      ],
    );
    final border = BoxDecoration(
      border: Border(bottom: BorderSide(color: PitPalette.outlineOf(context))),
    );
    if (children.isEmpty) {
      return Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(36, 8, 4, 8),
        alignment: Alignment.centerLeft,
        decoration: border,
        child: head,
      );
    }
    return DecoratedBox(
      decoration: border,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
          controlAffinity: ListTileControlAffinity.leading,
          minTileHeight: 64,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          shape: const Border(),
          collapsedShape: const Border(),
          title: head,
          children: children,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip.ready({
    required this.icon,
    required this.label,
    this.onTap,
    this.tooltip,
  }) : ready = true;
  const _Chip.neutral({required this.icon, required this.label})
    : ready = false,
      onTap = null,
      tooltip = null;

  final IconData icon;
  final String label;
  final bool ready;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = ready
        ? PitPalette.statusReadyOf(context)
        : PitPalette.inkMutedOf(context);
    final bg = ready
        ? fg.withValues(alpha: 0.2)
        : PitPalette.surfaceStrongOf(context);
    final radius = BorderRadius.circular(PitPalette.radiusSm);
    final chip = Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 112),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: ready ? fg : PitPalette.outlineOf(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final red = PitPalette.statusOverdueOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: red),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return CustomPaint(
      painter: _DashedRectPainter(color: PitPalette.outlineOf(context)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(PitPalette.radiusSm),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + 6, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.controller});
  final RobotLogsController controller;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.holdAuto();
  }

  late final _site = TextEditingController(text: widget.controller.site);
  late final _key = TextEditingController(text: widget.controller.uploadKey);
  late final _teams = TextEditingController(
    text: widget.controller.teams.join(', '),
  );
  late final _folder = TextEditingController(text: widget.controller.folder);
  bool _saving = false;
  bool _showKey = false;

  @override
  void dispose() {
    widget.controller.releaseAuto();
    for (final c in [_site, _key, _teams, _folder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    String message;
    try {
      message = await widget.controller.saveSettings(
        site: _site.text,
        uploadKey: _key.text,
        teams: [
          for (final t in _teams.text.split(RegExp(r'[\s,]+')))
            if (int.tryParse(t) != null) int.parse(t),
        ],
        folder: _folder.text,
      );
    } on Object catch (e) {
      message = 'Settings not saved: $e';
    }
    if (mounted) Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Robot logs settings'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _site,
              decoration: const InputDecoration(labelText: 'Log site'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: 'Upload key',
                helperText: 'Ask a mentor for it.',
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Hide key' : 'Show key',
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(
                    _showKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _teams,
              decoration: const InputDecoration(
                labelText: 'Teams',
                helperText: 'Which robot networks to scan: 3847 is 10.38.47.x.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _folder,
              decoration: const InputDecoration(labelText: 'Save files in'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Checking key' : 'Save'),
        ),
      ],
    );
  }
}

class _EditFileDialog extends StatefulWidget {
  const _EditFileDialog({required this.controller, required this.file});
  final RobotLogsController controller;
  final RobotLogFile file;

  @override
  State<_EditFileDialog> createState() => _EditFileDialogState();
}

class _EditFileDialogState extends State<_EditFileDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.holdAuto();
  }

  late final _name = TextEditingController(
    text: widget.file.name.replaceFirst(RegExp(r'\.(wpilog|rwnd)$'), ''),
  );
  late final _team = TextEditingController(
    text: widget.file.team?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    widget.controller.releaseAuto();
    _name.dispose();
    _team.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = widget.controller;
    final rel = widget.file.rel;
    final team = int.tryParse(_team.text.trim());
    if (_team.text.trim().isNotEmpty && team == null) {
      setState(() => _error = 'Team must be a number.');
      return;
    }
    if (team != widget.file.team) await c.setTeam(rel, team);
    if (!mounted) return;
    final current = widget.file.name.replaceFirst(
      RegExp(r'\.(wpilog|rwnd)$'),
      '',
    );
    if (_name.text.trim() != current && !await c.rename(rel, _name.text)) {
      if (mounted) setState(() => _error = 'The name cannot be empty.');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await widget.controller.resetName(widget.file.rel);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    return AlertDialog(
      title: const Text('Name on the log site'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              style: pitCodeStyle(context),
              decoration: InputDecoration(
                labelText: 'Name',
                suffixText: f.kind.extension,
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _team,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Team',
                helperText: 'Leave empty to use the team the file says.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Copied as ${f.original}',
              style: pitCodeStyle(
                context,
                color: PitPalette.inkMutedOf(context),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (f.nameEdited)
          TextButton(
            onPressed: _reset,
            child: const Text('Use suggested name'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
