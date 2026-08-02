import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/map_location.dart';
import '../services/map_image_store.dart';
import '../state/inventory_controller.dart';
import '../state/map_location_controller.dart';
import '../theme/pit_palette.dart';
import 'location_code.dart';

class MapsTab extends StatefulWidget {
  const MapsTab({
    required this.controller,
    required this.inventoryController,
    required this.imageStore,
    super.key,
  });

  final MapLocationController controller;
  final InventoryController inventoryController;
  final MapImageStore imageStore;

  @override
  State<MapsTab> createState() => _MapsTabState();
}

class _MapsTabState extends State<MapsTab> {
  MapType _mapType = MapType.lab;
  MapDiagram? _diagram;
  bool _loadingImage = true;

  bool _diagramActionInFlight = false;

  final Map<String, Offset> _dragPositions = {};

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final mapType = _mapType;
    MapDiagram? diagram;
    try {
      diagram = await widget.imageStore.diagramFor(mapType);
    } catch (error) {
      if (mounted && mapType == _mapType) {
        _showSyncError('load the diagram', error);
      }
    }

    if (!mounted || mapType != _mapType) return;
    setState(() {
      _diagram = diagram;
      _loadingImage = false;
    });
  }

  void _switchMapType(MapType mapType) {
    if (mapType == _mapType) return;
    setState(() {
      _mapType = mapType;
      _loadingImage = true;
      _dragPositions.clear();
    });
    _loadImage();
  }

  Future<void> _pickImage() async {
    if (_diagramActionInFlight) return;
    final target = _mapType;
    setState(() => _diagramActionInFlight = true);
    try {
      final pins = widget.controller.locationsForMap(target);
      if (pins.isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace diagram?'),
            content: Text(
              'There ${pins.length == 1 ? 'is 1 pin' : 'are ${pins.length} pins'} '
              'on this ${target.name} map. Replacing the diagram may misalign '
              'them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
      final diagram = await widget.imageStore.pickDiagram(target);
      if (diagram == null || !mounted) return;

      if (target != _mapType) return;
      setState(() => _diagram = diagram);
    } catch (error) {
      if (mounted && target == _mapType) {
        _showSyncError('pick the diagram', error);
      }
    } finally {
      if (mounted) setState(() => _diagramActionInFlight = false);
    }
  }

  Future<void> _removeImage() async {
    if (_diagramActionInFlight) return;
    final target = _mapType;
    setState(() => _diagramActionInFlight = true);
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove diagram?'),
          content: const Text(
            'This clears the map diagram for everyone. Existing pins stay and '
            'will reappear on the next diagram you set.',
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
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await widget.imageStore.clearDiagram(target);
      if (!mounted) return;

      if (target != _mapType) return;
      setState(() => _diagram = null);
    } catch (error) {
      if (mounted && target == _mapType) {
        _showSyncError('remove the diagram', error);
      }
    } finally {
      if (mounted) setState(() => _diagramActionInFlight = false);
    }
  }

  Future<void> _movePin(MapLocation pin, double x, double y) {
    return widget.controller
        .upsert(
          pin.copyWith(
            x: x.clamp(0.0, 1.0).toDouble(),
            y: y.clamp(0.0, 1.0).toDouble(),
            updatedAt: DateTime.now().toUtc(),
          ),
        )
        .catchError(
          (Object error) => _showSyncError('move "${pin.name}"', error),
        );
  }

  Future<void> _openEditor({MapLocation? pin}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _MapPinEditorSheet(
        pin: pin,
        mapType: _mapType,
        inventoryItems: widget.inventoryController.items,
        onSubmit: (result) {
          widget.controller
              .upsert(result)
              .catchError(
                (Object error) =>
                    _showSyncError('save "${result.name}"', error),
              );
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  Future<void> _openPinDetail(MapLocation pin) {
    final linked = pin.inventoryItemId == null
        ? null
        : widget.inventoryController.items.cast<InventoryItem?>().firstWhere(
            (item) => item?.id == pin.inventoryItemId,
            orElse: () => null,
          );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _PinDetailSheet(
        pin: pin,
        linkedItem: linked,
        onEdit: () {
          Navigator.of(sheetContext).pop();
          _openEditor(pin: pin);
        },
        onDelete: () async {
          final confirmed = await _confirmDelete(sheetContext, pin.name);
          if (!confirmed) return;
          try {
            await widget.controller.delete(pin.id);
          } catch (error) {
            _showSyncError('delete "${pin.name}"', error);
            return;
          }
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete pin?'),
        content: Text('Remove "$name" from the map. This cannot be undone.'),
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

  void _showSyncError(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not $action: $error')));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final pins = widget.controller.locationsForMap(_mapType);
        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<MapType>(
                          segments: const [
                            ButtonSegment(
                              value: MapType.lab,
                              label: Text('Lab'),
                              icon: Icon(Icons.home_work_outlined),
                            ),
                            ButtonSegment(
                              value: MapType.pit,
                              label: Text('Pit'),
                              icon: Icon(Icons.warehouse_outlined),
                            ),
                          ],
                          selected: {_mapType},
                          onSelectionChanged: (s) => _switchMapType(s.first),
                        ),
                      ),

                      if (_diagram != null && widget.imageStore.isSupported)
                        PopupMenuButton<String>(
                          tooltip: 'Diagram options',
                          enabled: !_diagramActionInFlight,
                          onSelected: (value) {
                            switch (value) {
                              case 'change':
                                unawaited(_pickImage());
                              case 'remove':
                                unawaited(_removeImage());
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'change',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.image_outlined),
                                title: Text('Change diagram'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.delete_outline_rounded),
                                title: Text('Remove diagram'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : _diagram == null
                      ? _EmptyMap(
                          mapType: _mapType,
                          supported: widget.imageStore.isSupported,
                          onChoose: _pickImage,
                        )
                      : _buildDiagram(context, pins),
                ),
              ],
            ),
            if (_diagram != null)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Add pin'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDiagram(BuildContext context, List<MapLocation> pins) {
    final diagram = _diagram!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final fitted = applyBoxFit(BoxFit.contain, diagram.size, box);

        final dest = Alignment.center.inscribe(
          fitted.destination,
          Offset.zero & box,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: Image(image: diagram.image, fit: BoxFit.contain),
            ),
            for (final pin in pins) _buildPin(pin, dest),
          ],
        );
      },
    );
  }

  static const double _pinSize = 32;

  static const double _pinTouchSize = 48;
  static const double _pinTouchInset = (_pinTouchSize - _pinSize) / 2;

  Widget _buildPin(MapLocation pin, Rect dest) {
    final fraction = _dragPositions[pin.id] ?? Offset(pin.x, pin.y);
    final center = Offset(
      dest.left + fraction.dx * dest.width,
      dest.top + fraction.dy * dest.height,
    );
    return Positioned(
      left: center.dx - _pinSize / 2 - _pinTouchInset,
      top: center.dy - _pinSize - _pinTouchInset,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openPinDetail(pin),
        onPanUpdate: (details) {
          final current = _dragPositions[pin.id] ?? Offset(pin.x, pin.y);
          setState(() {
            _dragPositions[pin.id] = Offset(
              (current.dx + details.delta.dx / dest.width)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              (current.dy + details.delta.dy / dest.height)
                  .clamp(0.0, 1.0)
                  .toDouble(),
            );
          });
        },
        onPanEnd: (_) {
          final fraction = _dragPositions[pin.id];
          _dragPositions.remove(pin.id);
          if (fraction != null) _movePin(pin, fraction.dx, fraction.dy);
        },
        child: SizedBox(
          width: _pinTouchSize,
          height: _pinTouchSize,
          child: Center(
            child: _PinGlyph(
              linked: pin.inventoryItemId != null,
              size: _pinSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _PinGlyph extends StatelessWidget {
  const _PinGlyph({required this.linked, required this.size});

  final bool linked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = PitPalette.accentOf(context);
    return SizedBox(
      width: size,
      height: size,
      child: Icon(
        linked ? Icons.location_on : Icons.location_on_outlined,
        color: accent,
        size: size,
      ),
    );
  }
}

class _EmptyMap extends StatelessWidget {
  const _EmptyMap({
    required this.mapType,
    required this.supported,
    required this.onChoose,
  });

  final MapType mapType;
  final bool supported;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final label = mapType == MapType.lab ? 'lab' : 'pit';
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
                Icon(Icons.map_outlined, size: 40, color: muted),
                const SizedBox(height: 12),
                Text(
                  'No $label diagram set',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  supported
                      ? 'Pick an image of the $label layout to start placing pins.'
                      : 'Diagram selection is not supported in the browser '
                            'preview.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: muted),
                ),
                if (supported) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onChoose,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Choose diagram'),
                  ),
                ],
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

class _PinDetailSheet extends StatelessWidget {
  const _PinDetailSheet({
    required this.pin,
    required this.linkedItem,
    required this.onEdit,
    required this.onDelete,
  });

  final MapLocation pin;
  final InventoryItem? linkedItem;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final muted = PitPalette.inkMutedOf(context);
    final item = linkedItem;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pin.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (item == null)
            Text(
              'No tool linked to this pin.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: muted),
            )
          else ...[
            Text(item.name, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                LocationCode(label: 'Lab', code: item.labLocation),
                LocationCode(label: 'Pit', code: item.pitLocation),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MapPinEditorSheet extends StatefulWidget {
  const _MapPinEditorSheet({
    required this.pin,
    required this.mapType,
    required this.inventoryItems,
    required this.onSubmit,
  });

  final MapLocation? pin;
  final MapType mapType;
  final List<InventoryItem> inventoryItems;
  final ValueChanged<MapLocation> onSubmit;

  @override
  State<_MapPinEditorSheet> createState() => _MapPinEditorSheetState();
}

class _MapPinEditorSheetState extends State<_MapPinEditorSheet> {
  late final TextEditingController _name;
  String? _linkedItemId;

  @override
  void initState() {
    super.initState();
    final pin = widget.pin;
    _name = TextEditingController(text: pin?.name ?? '');
    _linkedItemId = pin?.inventoryItemId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final existing = widget.pin;
    widget.onSubmit(
      MapLocation(
        id: existing?.id ?? 'map_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        mapType: widget.mapType,
        x: existing?.x ?? 0.5,
        y: existing?.y ?? 0.5,
        inventoryItemId: _linkedItemId,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.pin != null;
    return Padding(
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
            Text(
              editing ? 'Edit pin' : 'Add pin',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Battery cart',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _linkedItemId,
              decoration: const InputDecoration(labelText: 'Linked tool'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final item in widget.inventoryItems)
                  DropdownMenuItem(value: item.id, child: Text(item.name)),
              ],
              onChanged: (value) => setState(() => _linkedItemId = value),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: Text(editing ? 'Save' : 'Add pin'),
            ),
          ],
        ),
      ),
    );
  }
}
