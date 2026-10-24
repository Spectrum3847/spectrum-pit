import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/map_location.dart';
import '../services/map_location_sync_service.dart';
import '../services/spectrum_auth_service.dart';
import 'pit_controller_mixin.dart';

class MapLocationController extends ChangeNotifier
    with PitControllerMixin<MapLocation> {
  MapLocationController({
    required this._authService,
    required this._syncService,
  });

  static const String _cacheKey = 'pit_map_locations_cache';

  final SpectrumAuthService _authService;
  final MapLocationSyncService _syncService;

  @override
  String get pitCacheKey => _cacheKey;
  @override
  SpectrumAuthService get pitAuthService => _authService;

  @override
  MapLocation Function(String, Map<String, dynamic>) get pitItemFromJson =>
      MapLocation.fromJson;

  @override
  Stream<List<MapLocation>> pitStreamAll() => _syncService.streamAll();
  @override
  Future<void> pitUpsertRemote(MapLocation location) =>
      _syncService.upsert(location);
  @override
  Future<void> pitDeleteRemote(String id) => _syncService.delete(id);

  List<MapLocation> locationsForMap(MapType mapType) =>
      items.where((l) => l.mapType == mapType).toList();

  @override
  void dispose() {
    pitDispose();
    super.dispose();
  }
}
