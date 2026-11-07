import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';
import '../services/inventory_sync_service.dart';
import '../services/spectrum_auth_service.dart';
import 'pit_controller_mixin.dart';

class InventoryController extends ChangeNotifier
    with PitControllerMixin<InventoryItem> {
  InventoryController({required this._authService, required this._syncService});

  static const String _cacheKey = 'pit_inventory_cache';

  final SpectrumAuthService _authService;
  final InventorySyncService _syncService;

  @override
  String get pitCacheKey => _cacheKey;
  @override
  SpectrumAuthService get pitAuthService => _authService;

  @override
  InventoryItem Function(String, Map<String, dynamic>) get pitItemFromJson =>
      InventoryItem.fromJson;

  @override
  Stream<List<InventoryItem>> pitStreamAll() => _syncService.streamAll();
  @override
  Future<void> pitUpsertRemote(InventoryItem item) => _syncService.upsert(item);
  @override
  Future<void> pitDeleteRemote(String id) => _syncService.delete(id);

  @override
  void dispose() {
    pitDispose();
    super.dispose();
  }
}
