import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/photo_service.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';

enum PackingPhotoAction { replace, remove }

Future<PhotoSource?> choosePhotoSource(
  BuildContext context,
  List<PhotoSource> sources,
) async {
  if (sources.length == 1) return sources.single;
  return showModalBottomSheet<PhotoSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add packing photo',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final source in sources)
              _SourceOption(
                source: source,
                onTap: () => Navigator.of(sheetContext).pop(source),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({required this.source, required this.onTap});

  final PhotoSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (source) {
      PhotoSource.camera => (Icons.photo_camera_outlined, 'Take a photo'),
      PhotoSource.gallery => (
        Icons.photo_library_outlined,
        'Choose from library',
      ),
      PhotoSource.file => (Icons.folder_open_outlined, 'Choose a file'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PitPalette.surfaceOf(context),
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PitPalette.radiusSm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PitPalette.radiusSm),
              border: Border.all(color: PitPalette.outlineOf(context)),
            ),
            child: Row(
              children: [
                Icon(icon, color: PitPalette.inkOf(context)),
                const SizedBox(width: 12),
                Text(label, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PackingPhotoScreen extends StatefulWidget {
  const PackingPhotoScreen({
    required this.photoService,
    required this.photoRef,
    required this.itemId,
    required this.updatedAt,
    super.key,
  });

  final PhotoService photoService;
  final String photoRef;
  final String itemId;
  final DateTime updatedAt;

  @override
  State<PackingPhotoScreen> createState() => _PackingPhotoScreenState();
}

class _PackingPhotoScreenState extends State<PackingPhotoScreen> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    Uint8List? bytes;
    String? error;
    try {
      bytes = await widget.photoService.fetch(widget.photoRef);
    } catch (failure) {
      error = '$failure';
    }
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _error = error;
      _loading = false;
    });
  }

  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove photo?'),
        content: Text(
          'Delete the packing photo for "${widget.itemId}". The item stays on '
          'the list; the photo cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pop(PackingPhotoAction.remove);
  }

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.itemId.isEmpty ? 'Untitled item' : widget.itemId,
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _timestamp(widget.updatedAt),
              style: pitCodeStyle(context, color: muted),
            ),
          ],
        ),
      ),
      body: _buildBody(context),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: PitPalette.surfaceOf(context),
          border: Border(top: BorderSide(color: PitPalette.outlineOf(context))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(PackingPhotoAction.replace),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Replace'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _confirmRemove,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _overdueOf(context),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return _PhotoMessage(
        icon: Icons.error_outline_rounded,
        tone: _overdueOf(context),
        title: 'Photo did not load',
        body: error,
        onRetry: _load,
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const _PhotoMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Photos are unavailable',
        body: 'Sign in with your team account to see packing photos.',
      );
    }
    return InteractiveViewer(
      maxScale: 5,
      child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
    );
  }
}

String _timestamp(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

Color _overdueOf(BuildContext context) => PitPalette.statusOverdueOf(context);

class _PhotoMessage extends StatelessWidget {
  const _PhotoMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.tone,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? tone;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: tone ?? muted),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: muted),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
