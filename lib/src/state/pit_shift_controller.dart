import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pit_shift.dart';
import '../services/pit_shift_sync_service.dart';
import '../services/spectrum_auth_service.dart';
import 'pit_controller_mixin.dart';

class PitShiftController extends ChangeNotifier
    with PitControllerMixin<PitShift> {
  PitShiftController({required this._authService, required this._syncService});

  static const String _cacheKey = 'pit_shifts_cache';

  final SpectrumAuthService _authService;
  final PitShiftSyncService _syncService;

  @override
  String get pitCacheKey => _cacheKey;
  @override
  SpectrumAuthService get pitAuthService => _authService;

  @override
  PitShift Function(String, Map<String, dynamic>) get pitItemFromJson =>
      PitShift.fromJson;

  @override
  Stream<List<PitShift>> pitStreamAll() => _syncService.streamAll();
  @override
  Future<void> pitUpsertRemote(PitShift shift) => _syncService.upsert(shift);
  @override
  Future<void> pitDeleteRemote(String id) => _syncService.delete(id);

  List<PitShift> shiftsForCompetition(String competition) =>
      items.where((s) => s.competition == competition).toList()
        ..sort(_bySchedule);

  List<PitShift> shiftsForUid(String uid) =>
      items.where((s) => s.assignedUids.contains(uid)).toList()
        ..sort(_bySchedule);

  List<PitShiftConflict> get conflicts => findPitShiftConflicts(items);

  static int _bySchedule(PitShift a, PitShift b) {
    final byGroup = _group(a).compareTo(_group(b));
    if (byGroup != 0) return byGroup;
    if (a.hasMatchRange && b.hasMatchRange) {
      final byMatch = (a.startMatch ?? -1).compareTo(b.startMatch ?? -1);
      if (byMatch != 0) return byMatch;
    } else if (a.hasTimeRange && b.hasTimeRange) {
      final aStart = a.startsAt;
      final bStart = b.startsAt;
      if (aStart != null && bStart != null) {
        final byTime = aStart.compareTo(bStart);
        if (byTime != 0) return byTime;
      } else if (aStart != bStart) {
        return aStart == null ? -1 : 1;
      }
    }
    return a.label.compareTo(b.label);
  }

  static int _group(PitShift shift) {
    if (shift.hasMatchRange) return 0;
    if (shift.hasTimeRange) return 1;
    return 2;
  }

  @override
  void dispose() {
    pitDispose();
    super.dispose();
  }
}
