import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/packing_record.dart';
import '../services/packing_sync_service.dart';
import '../services/spectrum_auth_service.dart';
import 'pit_controller_mixin.dart';

class PackingController extends ChangeNotifier
    with PitControllerMixin<PackingRecord> {
  PackingController({
    required SpectrumAuthService authService,
    required PackingSyncService syncService,
  }) : _authService = authService,
       _syncService = syncService;

  static const String _cacheKey = 'pit_packing_cache';

  final SpectrumAuthService _authService;
  final PackingSyncService _syncService;

  @override
  String get pitCacheKey => _cacheKey;
  @override
  SpectrumAuthService get pitAuthService => _authService;

  @override
  PackingRecord Function(String, Map<String, dynamic>) get pitItemFromJson =>
      PackingRecord.fromJson;

  @override
  Stream<List<PackingRecord>> pitStreamAll() => _syncService.streamAll();
  @override
  Future<void> pitUpsertRemote(PackingRecord record) =>
      _syncService.upsert(record);
  @override
  Future<void> pitDeleteRemote(String id) => _syncService.delete(id);

  @override
  void dispose() {
    pitDispose();
    super.dispose();
  }
}
