import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/inventory_item.dart';
import '../models/packing_record.dart';
import '../services/container_photo_sync_service.dart';
import '../services/photo_service.dart';
import '../state/inventory_controller.dart';
import '../state/packing_controller.dart';
import '../theme/app_theme.dart';
import '../theme/pit_palette.dart';
import 'packing_photo.dart';
import '../widgets/keyboard_shortcuts.dart';

class PackingTab extends StatefulWidget {
  const PackingTab({
    required this.controller,
    required this.photoService,
    required this.inventoryController,
    required this.containerPhotoSyncService,
    super.key,
  });

  final PackingController controller;
  final PhotoService photoService;
  final InventoryController inventoryController;
  final ContainerPhotoSyncService containerPhotoSyncService;

  @override
  State<PackingTab> createState() => _PackingTabState();
}

class _PackingTabState extends State<PackingTab> {
  final Set<String> _busy = <String>{};

  final Set<String> _advancing = <String>{};

  final Set<String> _busyContainerPhotos = <String>{};

  final Set<String> _containerPhotoChecks = <String>{};

  final Set<String> _containerPhotoLoadFailed = <String>{};

  final Map<String, String?> _containerPhotoKeys = <String, String?>{};

  final Map<String, int> _containerPhotoWrites = <String, int>{};

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.inventoryController,
      ]),
      builder: (context, _) {
        final rows = _groupedRows(_mergedRows());
        final entries = _boardEntries(rows);
        return Stack(
          children: [
            rows.isEmpty
                ? _EmptyBoard(onAdd: () => _openEditor())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      final location = entry.location;
                      if (location != null) {
                        if (!_containerPhotoChecks.contains(location) &&
                            !_containerPhotoLoadFailed.contains(location)) {
                          _containerPhotoChecks.add(location);
                          _loadContainerPhoto(location);
                        }
                        return _LocationHeader(
                          location: location,
                          hasPhoto: _containerPhotoKeys[location] != null,
                          busy: _busyContainerPhotos.contains(location),
                          loadFailed: _containerPhotoLoadFailed.contains(
                            location,
                          ),
                          onPhotoTap: () => _handleContainerPhoto(location),
                        );
                      }
                      final row = entry.row!;
                      return _PackingRow(
                        record: row.record,
                        displayName: _displayName(row),
                        photoService: widget.photoService,
                        photoBusy: _busy.contains(row.record.id),
                        onTap: () => _openEditor(row: row),
                        onAdvance: () => _advance(row),
                        onPhotoTap: () => _handlePhoto(row.record),
                      );
                    },
                  ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: null,
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _advance(_PackingRowData row) {
    final id = row.record.id;
    if (_advancing.contains(id)) return Future<void>.value();
    _advancing.add(id);
    final status = _nextStatus(row.record.packingStatus);
    final record = row.virtual
        ? PackingRecord(
            id: id,
            itemId: row.record.itemId,
            packingStatus: status,
            updatedAt: DateTime.now().toUtc(),
          )
        : row.record.copyWith(
            packingStatus: status,
            updatedAt: DateTime.now().toUtc(),
          );
    return widget.controller
        .upsert(record)
        .catchError(
          (Object error) =>
              _showFailure('update "${row.record.itemId}"', error),
        )
        .whenComplete(() => _advancing.remove(id));
  }

  Future<void> _handlePhoto(PackingRecord record) {
    if (_busy.contains(record.id)) return Future<void>.value();
    return record.photoRef == null ? _capture(record) : _openPhoto(record);
  }

  Future<void> _capture(PackingRecord record) async {
    final source = await choosePhotoSource(
      context,
      widget.photoService.sources,
    );
    if (source == null || !mounted) return;
    setState(() => _busy.add(record.id));
    String? key;
    try {
      key = await widget.photoService.capture(source);
    } catch (error) {
      _showFailure('add a photo to "${record.itemId}"', error);
    } finally {
      if (mounted) setState(() => _busy.remove(record.id));
    }
    if (key == null) return;
    if (!mounted) {
      await _deleteKey(key, record.itemId);
      return;
    }

    final current = _current(record);
    try {
      await widget.controller.upsert(
        current.copyWith(photoRef: key, updatedAt: DateTime.now().toUtc()),
      );
    } catch (error) {
      _showFailure('save the photo for "${current.itemId}"', error);
      await _deleteKey(key, current.itemId);
      return;
    }
    final previous = current.photoRef;
    if (previous != null) await _deleteKey(previous, current.itemId);
  }

  Future<void> _openPhoto(PackingRecord record) async {
    final action = await Navigator.of(context).push<PackingPhotoAction>(
      MaterialPageRoute<PackingPhotoAction>(
        builder: (_) => PackingPhotoScreen(
          photoService: widget.photoService,
          photoRef: record.photoRef!,
          itemId: record.itemId,
          updatedAt: record.updatedAt,
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case PackingPhotoAction.replace:
        await _capture(_current(record));
      case PackingPhotoAction.remove:
        await _removePhoto(_current(record));
    }
  }

  Future<void> _removePhoto(PackingRecord record) async {
    final key = record.photoRef;
    if (key == null) return;
    try {
      await widget.controller.upsert(
        record.copyWith(clearPhotoRef: true, updatedAt: DateTime.now().toUtc()),
      );
    } catch (error) {
      _showFailure('remove the photo from "${record.itemId}"', error);
      return;
    }
    await _deleteKey(key, record.itemId);
  }

  Future<void> _deleteKey(String key, String itemId) async {
    try {
      await widget.photoService.delete(key);
    } catch (error) {
      _showFailure('delete the old photo for "$itemId"', error);
    }
  }

  Future<void> _loadContainerPhoto(String location) async {
    final writes = _containerPhotoWrites[location] ?? 0;
    String? key;
    var failed = false;
    try {
      key = await widget.containerPhotoSyncService.readKey(location);
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;

    if ((_containerPhotoWrites[location] ?? 0) != writes) return;
    setState(() {
      if (failed) {
        _containerPhotoLoadFailed.add(location);
        _containerPhotoChecks.remove(location);
      } else {
        _containerPhotoLoadFailed.remove(location);
        _containerPhotoKeys[location] = key;
      }
    });
  }

  Future<void> _handleContainerPhoto(String location) {
    if (_busyContainerPhotos.contains(location)) return Future<void>.value();
    if (_containerPhotoLoadFailed.contains(location)) {
      _containerPhotoChecks.add(location);
      return _loadContainerPhoto(location);
    }
    final key = _containerPhotoKeys[location];
    return key == null
        ? _captureContainerPhoto(location)
        : _openContainerPhoto(location, key);
  }

  Future<void> _captureContainerPhoto(String location) async {
    final source = await choosePhotoSource(
      context,
      widget.photoService.sources,
    );
    if (source == null || !mounted) return;
    setState(() => _busyContainerPhotos.add(location));
    final previous = _containerPhotoKeys[location];
    String? key;
    try {
      key = await widget.photoService.capture(source);
      if (key == null) return;
      if (!mounted) {
        await _deleteKey(key, location);
        return;
      }
      await widget.containerPhotoSyncService.writeKey(location, key);
      _markContainerPhotoWritten(location);
      if (!mounted) return;
      setState(() {
        _containerPhotoKeys[location] = key;

        _containerPhotoLoadFailed.remove(location);
      });
      if (previous != null && previous != key) {
        await _deleteKey(previous, location);
      }
    } catch (error) {
      _showFailure('add a photo to "$location"', error);
      if (key != null) await _deleteKey(key, location);
    } finally {
      if (mounted) setState(() => _busyContainerPhotos.remove(location));
    }
  }

  Future<void> _openContainerPhoto(String location, String key) async {
    final action = await Navigator.of(context).push<PackingPhotoAction>(
      MaterialPageRoute<PackingPhotoAction>(
        builder: (_) => PackingPhotoScreen(
          photoService: widget.photoService,
          photoRef: key,

          itemId: location,
          updatedAt: DateTime.now().toUtc(),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case PackingPhotoAction.replace:
        await _captureContainerPhoto(location);
      case PackingPhotoAction.remove:
        await _removeContainerPhoto(location, key);
    }
  }

  Future<void> _removeContainerPhoto(String location, String key) async {
    try {
      await widget.containerPhotoSyncService.clearKey(location);
    } catch (error) {
      _showFailure('remove the photo from "$location"', error);
      return;
    }
    _markContainerPhotoWritten(location);
    await _deleteKey(key, location);
    if (!mounted) return;
    setState(() {
      _containerPhotoKeys[location] = null;
      _containerPhotoLoadFailed.remove(location);
    });
  }

  void _markContainerPhotoWritten(String location) =>
      _containerPhotoWrites[location] =
          (_containerPhotoWrites[location] ?? 0) + 1;

  PackingRecord _current(PackingRecord record) => widget.controller.items
      .firstWhere((item) => item.id == record.id, orElse: () => record);

  List<_PackingRowData> _mergedRows() {
    final records = widget.controller.items;
    final inventoryItems = widget.inventoryController.items;
    final rows = <_PackingRowData>[];
    for (final item in inventoryItems) {
      PackingRecord? match;
      for (final record in records) {
        if (record.itemId == item.id) {
          match = record;
          break;
        }
      }
      rows.add(
        match == null
            ? (record: _virtualRecord(item), item: item, virtual: true)
            : (record: match, item: item, virtual: false),
      );
    }
    final inventoryIds = {for (final item in inventoryItems) item.id};
    for (final record in records) {
      if (inventoryIds.contains(record.itemId)) continue;
      rows.add((record: record, item: null, virtual: false));
    }
    return rows;
  }

  List<_PackingRowData> _groupedRows(List<_PackingRowData> rows) {
    final byLocation = <String, List<_PackingRowData>>{};
    final order = <String>[];
    final ungrouped = <_PackingRowData>[];
    for (final row in rows) {
      final location = row.item?.pitLocation.trim() ?? '';
      if (location.isEmpty) {
        ungrouped.add(row);
        continue;
      }
      if (!byLocation.containsKey(location)) order.add(location);
      byLocation.putIfAbsent(location, () => []).add(row);
    }
    return [
      for (final location in order) ...byLocation[location]!,
      ...ungrouped,
    ];
  }

  List<_BoardEntry> _boardEntries(List<_PackingRowData> rows) {
    final entries = <_BoardEntry>[];
    String? current;
    for (final row in rows) {
      final location = row.item?.pitLocation.trim() ?? '';
      if (location.isNotEmpty && location != current) {
        entries.add((location: location, row: null));
        current = location;
      }
      if (location.isEmpty) current = null;
      entries.add((location: null, row: row));
    }
    return entries;
  }

  PackingRecord _virtualRecord(InventoryItem item) => PackingRecord(
    id: item.id,
    itemId: item.id,
    packingStatus: PackingStatus.notStarted,
    updatedAt: item.updatedAt,
  );

  void _showFailure(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not $action: $error')));
  }

  Future<void> _openEditor({_PackingRowData? row}) {
    final record = (row == null || row.virtual) ? null : row.record;
    final item = row?.item;
    final label = item?.name ?? record?.itemId ?? '';
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RecordEditorSheet(
        record: record,
        item: item,
        photoService: widget.photoService,
        onSubmit: (result) async {
          try {
            await widget.controller.upsert(result);
            return true;
          } catch (error) {
            _showFailure('save "${result.itemId}"', error);
            return false;
          }
        },
        onDelete: record == null
            ? null
            : () async {
                final confirmed = await _confirmDelete(sheetContext, label);
                if (!confirmed) return;
                var deleted = false;

                final photoRef = _current(record).photoRef;
                try {
                  await widget.controller.delete(record.id);
                  deleted = true;
                } catch (error) {
                  _showFailure('delete "$label"', error);
                }

                if (deleted && photoRef != null) {
                  await _deleteKey(photoRef, label);
                }

                if (!deleted) return;
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String itemId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete packing record?'),
        content: Text(
          'Remove item "$itemId" from the packing list. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

typedef _PackingRowData = ({
  PackingRecord record,
  InventoryItem? item,
  bool virtual,
});

typedef _BoardEntry = ({String? location, _PackingRowData? row});

String _displayName(_PackingRowData row) =>
    row.item?.name ??
    (row.record.itemId.isEmpty ? 'Untitled item' : row.record.itemId);

PackingStatus _nextStatus(PackingStatus status) => switch (status) {
  PackingStatus.notStarted => PackingStatus.packing,
  PackingStatus.packing => PackingStatus.staging,
  PackingStatus.staging => PackingStatus.loading,
  PackingStatus.loading => PackingStatus.ready,
  PackingStatus.ready => PackingStatus.packing,
};

String _statusLabel(PackingStatus status) => switch (status) {
  PackingStatus.notStarted => 'Not started',
  PackingStatus.packing => 'Packing',
  PackingStatus.staging => 'Staging',
  PackingStatus.loading => 'Loading',
  PackingStatus.ready => 'Ready',
};

IconData _statusIcon(PackingStatus status) => switch (status) {
  PackingStatus.notStarted => Icons.radio_button_unchecked,
  PackingStatus.packing => Icons.inventory_2_outlined,
  PackingStatus.staging => Icons.move_up_rounded,
  PackingStatus.loading => Icons.local_shipping_outlined,
  PackingStatus.ready => Icons.check_circle_outline,
};

Color _statusColor(BuildContext context, PackingStatus status) {
  return switch (status) {
    PackingStatus.notStarted => PitPalette.inkMutedOf(context),
    PackingStatus.packing => PitPalette.statusPackingOf(context),
    PackingStatus.staging => PitPalette.statusStagingOf(context),
    PackingStatus.loading => PitPalette.statusLoadingOf(context),
    PackingStatus.ready => PitPalette.statusReadyOf(context),
  };
}

class _PackingRow extends StatelessWidget {
  const _PackingRow({
    required this.record,
    required this.displayName,
    required this.photoService,
    required this.photoBusy,
    required this.onTap,
    required this.onAdvance,
    required this.onPhotoTap,
  });

  final PackingRecord record;

  final String displayName;
  final PhotoService photoService;
  final bool photoBusy;
  final VoidCallback onTap;
  final VoidCallback onAdvance;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PitPalette.radiusSm),
              border: Border.all(color: PitPalette.outlineOf(context)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _PhotoSlot(
                  photoRef: record.photoRef,
                  photoService: photoService,
                  busy: photoBusy,
                  onTap: onPhotoTap,
                ),
                const SizedBox(width: 8),
                _StatusChip(status: record.packingStatus, onTap: onAdvance),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.onTap});

  final PackingStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    final fg = color;
    final bg = color.withValues(alpha: 0.2);

    return Tooltip(
      message: '${_statusLabel(status)}. Tap to advance the packing stage.',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(PitPalette.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PitPalette.radiusSm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PitPalette.radiusSm),
              border: Border.all(color: color),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_statusIcon(status), size: 16, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _statusLabel(status),
                      softWrap: false,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: fg),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({
    required this.location,
    required this.hasPhoto,
    required this.busy,
    required this.loadFailed,
    required this.onPhotoTap,
  });

  final String location;
  final bool hasPhoto;
  final bool busy;
  final bool loadFailed;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              location.toUpperCase(),
              style: pitCodeStyle(context, color: PitPalette.inkOf(context)),
            ),
          ),
          IconButton(
            onPressed: busy ? null : onPhotoTap,
            tooltip: loadFailed
                ? 'Could not check for a container photo -- tap to retry'
                : hasPhoto
                ? 'Open the container photo'
                : 'Add a container photo',
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    loadFailed
                        ? Icons.cloud_off_rounded
                        : hasPhoto
                        ? Icons.photo_outlined
                        : Icons.photo_camera_outlined,
                    color: hasPhoto && !loadFailed
                        ? PitPalette.accentOf(context)
                        : muted,
                  ),
          ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatefulWidget {
  const _PhotoSlot({
    required this.photoRef,
    required this.photoService,
    required this.busy,
    required this.onTap,
    this.size = 48,
  });

  final String? photoRef;
  final PhotoService photoService;

  final bool busy;
  final VoidCallback onTap;

  final double size;

  @override
  State<_PhotoSlot> createState() => _PhotoSlotState();
}

class _PhotoSlotState extends State<_PhotoSlot> {
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final ref = widget.photoRef;
    if (ref != null) {
      _loading = true;
      _fetch(ref);
    }
  }

  @override
  void didUpdateWidget(_PhotoSlot old) {
    super.didUpdateWidget(old);
    if (old.photoRef == widget.photoRef) return;
    final ref = widget.photoRef;
    setState(() {
      _bytes = null;
      _failed = false;
      _loading = ref != null;
    });
    if (ref != null) _fetch(ref);
  }

  void _retry() {
    final ref = widget.photoRef;
    if (ref == null) return;
    setState(() {
      _failed = false;
      _loading = true;
    });
    _fetch(ref);
  }

  Future<void> _fetch(String ref) async {
    Uint8List? bytes;
    var failed = false;
    try {
      bytes = await widget.photoService.fetch(ref);
    } catch (_) {
      failed = true;
    }

    if (!mounted || ref != widget.photoRef) return;
    setState(() {
      _bytes = bytes;
      _failed = failed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final empty = widget.photoRef == null;
    final size = widget.size;
    final radius = BorderRadius.circular(PitPalette.radiusSm);
    final (child, hint) = _content(context, muted);
    return Tooltip(
      message: hint,
      child: Material(
        color: empty ? null : PitPalette.surfaceStrongOf(context),
        borderRadius: radius,
        child: InkWell(
          onTap: _failed ? _retry : widget.onTap,
          borderRadius: radius,
          child: SizedBox(
            width: size,
            height: size,
            child: empty
                ? CustomPaint(
                    painter: _DashedRectPainter(
                      color: PitPalette.outlineOf(context),
                      radius: PitPalette.radiusSm,
                    ),
                    child: Center(child: child),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: PitPalette.outlineOf(context)),
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Center(child: child),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  (Widget, String) _content(BuildContext context, Color muted) {
    final glyph = math.max(20.0, widget.size * 0.34);
    if (widget.busy) {
      return (
        SizedBox(
          width: glyph,
          height: glyph,
          child: CircularProgressIndicator(strokeWidth: 2, color: muted),
        ),
        'Uploading the photo',
      );
    }
    if (widget.photoRef == null) {
      return (
        Icon(Icons.add_a_photo_outlined, size: glyph, color: muted),
        'Add a packing photo',
      );
    }
    if (_loading) {
      return (
        SizedBox(
          width: glyph,
          height: glyph,
          child: CircularProgressIndicator(strokeWidth: 2, color: muted),
        ),
        'Loading the photo',
      );
    }
    if (_failed) {
      return (
        Icon(
          Icons.error_outline_rounded,
          size: glyph,
          color: PitPalette.statusOverdueOf(context),
        ),
        'Photo did not load. Tap to try again.',
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return (
        Icon(Icons.cloud_off_rounded, size: glyph, color: muted),
        'Sign in with your team account to see photos',
      );
    }
    return (
      Image.memory(
        bytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      'Open the packing photo',
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.photoRef,
    required this.photoService,
    required this.busy,
    required this.size,
    required this.onTap,
  });

  final String? photoRef;
  final PhotoService photoService;
  final bool busy;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ref = photoRef;
    if (ref != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _PhotoSlot(
          photoRef: ref,
          photoService: photoService,
          busy: busy,
          onTap: onTap,
          size: size,
        ),
      );
    }
    final muted = PitPalette.inkMutedOf(context);
    final glyph = math.max(20.0, size * 0.34);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          borderRadius: BorderRadius.circular(PitPalette.radiusSm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(PitPalette.radiusSm),
            child: CustomPaint(
              painter: _DashedRectPainter(
                color: PitPalette.outlineOf(context),
                radius: PitPalette.radiusSm,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy)
                      SizedBox(
                        width: glyph,
                        height: glyph,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: muted,
                        ),
                      )
                    else
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: glyph,
                        color: muted,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      busy ? 'Uploading' : 'Add photo',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: CustomPaint(
          painter: _DashedRectPainter(
            color: PitPalette.outlineOf(context),
            radius: PitPalette.radiusSm,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 40, color: muted),
                const SizedBox(height: 12),
                Text(
                  'The packing list is empty',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Add items to start tracking the load-out.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add item'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}

class _RecordEditorSheet extends StatefulWidget {
  const _RecordEditorSheet({
    required this.photoService,
    required this.onSubmit,
    this.record,
    this.item,
    this.onDelete,
  });

  final PackingRecord? record;

  final InventoryItem? item;
  final PhotoService photoService;

  final Future<bool> Function(PackingRecord record) onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<_RecordEditorSheet> createState() => _RecordEditorSheetState();
}

class _RecordEditorSheetState extends State<_RecordEditorSheet> {
  static const double _photoSize = 120;

  late final TextEditingController _itemId;
  late PackingStatus _status;

  String? _photoRef;

  late final String? _originalPhotoRef;

  final List<String> _capturedKeys = <String>[];

  bool _saved = false;

  bool _saving = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    final item = widget.item;
    _itemId = TextEditingController(text: item?.name ?? record?.itemId ?? '');
    _status =
        record?.packingStatus ??
        (item != null ? PackingStatus.notStarted : PackingStatus.packing);
    _photoRef = record?.photoRef;
    _originalPhotoRef = record?.photoRef;
  }

  @override
  void dispose() {
    _itemId.dispose();

    if (!_saved && !_saving) {
      for (final key in _capturedKeys) {
        widget.photoService.delete(key).catchError((_) {});
      }
    }
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_busy) return;
    final source = await choosePhotoSource(
      context,
      widget.photoService.sources,
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    String? key;
    try {
      key = await widget.photoService.capture(source);
    } catch (error) {
      _showFailure('add a photo', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (key == null) return;
    if (!mounted) {
      await widget.photoService.delete(key).catchError((_) {});
      return;
    }

    final captured = key;
    setState(() {
      _photoRef = captured;
      _capturedKeys.add(captured);
    });
  }

  void _showFailure(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not $action: $error')));
  }

  Future<void> _save() async {
    final item = widget.item;
    final itemId = item?.id ?? _itemId.text.trim();
    if (itemId.isEmpty) return;
    if (_saving) return;
    setState(() => _saving = true);
    final existing = widget.record;
    bool committed;
    try {
      committed = await widget.onSubmit(
        PackingRecord(
          id: item?.id ?? existing?.id ?? const Uuid().v4(),
          itemId: itemId,
          packingStatus: _status,
          photoRef: _photoRef,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } finally {
      _saving = false;
    }
    if (!mounted || !committed) return;
    _saved = true;

    final claimed = _photoRef;
    for (final key in _capturedKeys) {
      if (key != claimed) {
        try {
          await widget.photoService.delete(key);
        } catch (_) {}
      }
    }
    final original = _originalPhotoRef;
    if (original != null && original != claimed) {
      try {
        await widget.photoService.delete(original);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.record != null;

    final canSave = widget.item != null || _itemId.text.trim().isNotEmpty;

    return SaveShortcut(
      onSave: _save,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editing ? 'Edit packing item' : 'Add packing item',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Delete',
                      onPressed: widget.onDelete,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.item != null)
                TextField(
                  controller: _itemId,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Item name'),
                )
              else
                TextField(
                  controller: _itemId,
                  autofocus: !editing,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    hintText: 'DeWalt Drill Kit',
                  ),
                ),
              const SizedBox(height: 16),
              _PhotoSection(
                photoRef: _photoRef,
                photoService: widget.photoService,
                busy: _busy,
                size: _photoSize,
                onTap: _capturePhoto,
              ),
              const SizedBox(height: 16),
              Text(
                'Packing status',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: PitPalette.inkMutedOf(context),
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<PackingStatus>(
                segments: [
                  for (final status in PackingStatus.values)
                    ButtonSegment<PackingStatus>(
                      value: status,

                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_statusLabel(status), softWrap: false),
                      ),
                      icon: Icon(_statusIcon(status)),
                    ),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: canSave ? _save : null,
                child: Text(editing ? 'Save' : 'Add item'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
