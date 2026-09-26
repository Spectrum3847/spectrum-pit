import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/scout_shift_mirror.dart';
import '../services/scout_shift_mirror_sync_service.dart';
import '../services/spectrum_auth_service.dart';

class ScoutShiftMirrorController extends ChangeNotifier {
  ScoutShiftMirrorController({
    required this._authService,
    required this._syncService,
  });

  final SpectrumAuthService _authService;
  final ScoutShiftMirrorSyncService _syncService;

  Future<void>? _bootstrapFuture;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  StreamSubscription<List<ScoutShiftMirror>>? _streamSubscription;
  bool _disposed = false;

  int _streamGeneration = 0;

  List<ScoutShiftMirror> _items = <ScoutShiftMirror>[];

  List<ScoutShiftMirror> get items => List.unmodifiable(_items);

  ScoutShiftMirror? forCompetition(String competition) {
    for (final item in _items) {
      if (item.competition == competition) return item;
    }
    return null;
  }

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
    _authSubscription = _authService.snapshotStream.listen(_onAuthSnapshot);
    if (_disposed) {
      _authSubscription?.cancel();
      _authSubscription = null;
      return;
    }
    _onAuthSnapshot(_authService.snapshot);
  }

  void _onAuthSnapshot(SpectrumAuthSnapshot snapshot) {
    if (_disposed) return;
    if (snapshot.state == SpectrumAuthState.signedIn && snapshot.user != null) {
      final gen = ++_streamGeneration;
      _streamSubscription?.cancel();
      _streamSubscription = _syncService.streamAll().listen(
        (items) {
          if (gen != _streamGeneration) return;
          _items = items;
          notifyListeners();
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
      _items = <ScoutShiftMirror>[];
      notifyListeners();
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
