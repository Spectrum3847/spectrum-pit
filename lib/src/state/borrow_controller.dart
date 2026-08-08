import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/borrow_record.dart';
import '../services/borrow_sync_service.dart';
import '../services/spectrum_auth_service.dart';
import 'pit_controller_mixin.dart';

class BorrowController extends ChangeNotifier
    with PitControllerMixin<BorrowRecord> {
  BorrowController({
    required SpectrumAuthService authService,
    required BorrowSyncService syncService,
  }) : _authService = authService,
       _syncService = syncService;

  static const String _cacheKey = 'pit_borrow_cache';

  final SpectrumAuthService _authService;
  final BorrowSyncService _syncService;

  @override
  String get pitCacheKey => _cacheKey;
  @override
  SpectrumAuthService get pitAuthService => _authService;

  @override
  BorrowRecord Function(String, Map<String, dynamic>) get pitItemFromJson =>
      BorrowRecord.fromJson;

  @override
  Stream<List<BorrowRecord>> pitStreamAll() => _syncService.streamAll();
  @override
  Future<void> pitUpsertRemote(BorrowRecord record) =>
      _syncService.upsert(record);
  @override
  Future<void> pitDeleteRemote(String id) => _syncService.delete(id);

  int get overdueCount =>
      items.where((record) => record.isOverdueAt(DateTime.now())).length;

  @override
  void dispose() {
    pitDispose();
    super.dispose();
  }
}
