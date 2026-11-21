import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/active_event.dart';
import '../services/active_event_sync_service.dart';
import '../services/spectrum_auth_service.dart';

class ActiveEventController extends ChangeNotifier {
  ActiveEventController({
    required this._authService,
    required this._syncService,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String cacheKey = 'active_event_v1';

  final SpectrumAuthService _authService;
  final ActiveEventSyncService _syncService;
  final DateTime Function() _clock;

  Future<void>? _bootstrapFuture;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  StreamSubscription<ActiveEvent?>? _streamSubscription;
  int _streamGeneration = 0;
  bool _disposed = false;

  ActiveEvent? _event;

  ActiveEvent? get event => _event;

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _doBootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _doBootstrap() async {
    await _loadCache();
    if (_disposed) return;
    _authSubscription = _authService.snapshotStream.listen(_onAuthSnapshot);
    _onAuthSnapshot(_authService.snapshot);
  }

  void _onAuthSnapshot(SpectrumAuthSnapshot snapshot) {
    if (_disposed) return;
    if (snapshot.state == SpectrumAuthState.signedIn && snapshot.user != null) {
      final gen = ++_streamGeneration;
      _streamSubscription?.cancel();
      _streamSubscription = _syncService.watch().listen(
        (event) {
          if (gen != _streamGeneration) return;
          _apply(event);
        },
        onError: (Object error) {
          if (gen != _streamGeneration) return;
          debugPrint('$runtimeType sync stream error: $error');
        },
      );
    } else if (snapshot.state == SpectrumAuthState.signedOut) {
      ++_streamGeneration;
      _streamSubscription?.cancel();
      _streamSubscription = null;
    }
  }

  Future<void> select({
    required String eventKey,
    required String eventName,
  }) async {
    final previous = _event;
    final next = ActiveEvent(
      eventKey: eventKey,
      eventName: eventName,
      updatedAt: _clock().toUtc(),
    );
    _apply(next);
    try {
      await _syncService.write(next);
    } catch (_) {
      if (identical(_event, next)) _apply(previous);
      rethrow;
    }
  }

  void _apply(ActiveEvent? event) {
    if (_disposed || event == _event) return;
    _event = event;
    unawaited(_saveCache(event));
    notifyListeners();
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      _event = ActiveEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _event = null;
    }
  }

  Future<void> _saveCache(ActiveEvent? event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (event == null) {
        await prefs.remove(cacheKey);
      } else {
        await prefs.setString(cacheKey, jsonEncode(event.toJson()));
      }
    } catch (error) {
      debugPrint('$runtimeType cache write failed: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    _streamSubscription?.cancel();
    super.dispose();
  }
}
