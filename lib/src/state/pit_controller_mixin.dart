import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pit_model.dart';
import '../services/spectrum_auth_service.dart';

mixin PitControllerMixin<T extends PitModel> on ChangeNotifier {
  String get pitCacheKey;

  T Function(String id, Map<String, dynamic> data) get pitItemFromJson;

  SpectrumAuthService get pitAuthService;

  Stream<List<T>> pitStreamAll();

  Future<void> pitUpsertRemote(T item);

  Future<void> pitDeleteRemote(String id);

  Future<void>? _pitBootstrapFuture;
  StreamSubscription<SpectrumAuthSnapshot>? _pitAuthSubscription;
  StreamSubscription<List<T>>? _pitStreamSubscription;

  bool _pitDisposed = false;

  int _pitStreamGeneration = 0;

  Future<void> _pitCacheSaveChain = Future<void>.value();

  List<T> _pitItems = <T>[];

  List<T> get items => List.unmodifiable(_pitItems);

  Future<void> bootstrap() {
    return _pitBootstrapFuture ??= _pitDoBootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _pitBootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> upsert(T item) async {
    final previousIndex = _pitItems.indexWhere((e) => e.id == item.id);
    final previousItem = previousIndex < 0 ? null : _pitItems[previousIndex];
    _pitItems = [
      for (final existing in _pitItems)
        if (existing.id != item.id) existing,
      item,
    ];
    notifyListeners();
    try {
      await pitUpsertRemote(item);
    } catch (_) {
      final restored = [
        for (final existing in _pitItems)
          if (existing.id != item.id) existing,
      ];
      if (previousItem != null) {
        restored.insert(previousIndex.clamp(0, restored.length), previousItem);
      }
      _pitItems = restored;
      notifyListeners();

      await _pitSaveCache().catchError((_) {});
      rethrow;
    }

    await _pitSaveCache().catchError((_) {});
  }

  Future<void> delete(String id) async {
    final previousIndex = _pitItems.indexWhere((e) => e.id == id);
    final previousItem = previousIndex < 0 ? null : _pitItems[previousIndex];
    _pitItems = [
      for (final existing in _pitItems)
        if (existing.id != id) existing,
    ];
    notifyListeners();
    try {
      await pitDeleteRemote(id);
    } catch (_) {
      if (previousItem != null) {
        final restored = [
          for (final existing in _pitItems)
            if (existing.id != id) existing,
        ];
        restored.insert(previousIndex.clamp(0, restored.length), previousItem);
        _pitItems = restored;
      }
      notifyListeners();

      await _pitSaveCache().catchError((_) {});
      rethrow;
    }

    await _pitSaveCache().catchError((_) {});
  }

  void pitDispose() {
    _pitDisposed = true;
    _pitAuthSubscription?.cancel();
    _pitStreamSubscription?.cancel();
  }

  Future<void> _pitDoBootstrap() async {
    await _pitLoadCache();
    if (_pitDisposed) return;
    notifyListeners();
    _pitAuthSubscription = pitAuthService.snapshotStream.listen(
      _pitOnAuthSnapshot,
    );
    if (_pitDisposed) {
      _pitAuthSubscription?.cancel();
      _pitAuthSubscription = null;
      return;
    }
    _pitOnAuthSnapshot(pitAuthService.snapshot);
  }

  void _pitOnAuthSnapshot(SpectrumAuthSnapshot snapshot) {
    if (_pitDisposed) return;
    if (snapshot.state == SpectrumAuthState.signedIn && snapshot.user != null) {
      final gen = ++_pitStreamGeneration;
      _pitStreamSubscription?.cancel();
      _pitStreamSubscription = pitStreamAll().listen(
        (items) {
          if (gen != _pitStreamGeneration) return;
          _pitItems = items;
          _pitSaveCache();
          notifyListeners();
        },
        onError: (Object error) {
          if (gen != _pitStreamGeneration) return;
          debugPrint('$runtimeType sync stream error: $error');
        },
      );
    } else if (snapshot.state == SpectrumAuthState.signedOut) {
      ++_pitStreamGeneration;
      _pitStreamSubscription?.cancel();
      _pitStreamSubscription = null;
      notifyListeners();
    }
  }

  Future<void> _pitLoadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(pitCacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _pitItems = decoded
          .cast<Map<String, dynamic>>()
          .map((map) => pitItemFromJson(map['id'] as String, map))
          .toList();
    } catch (_) {
      _pitItems = <T>[];
    }
  }

  Future<void> _pitSaveCache() {
    final encoded = jsonEncode([
      for (final item in _pitItems) {...item.toJson(), 'id': item.id},
    ]);
    final write = _pitCacheSaveChain.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pitCacheKey, encoded);
    });

    _pitCacheSaveChain = write.catchError((_) {});
    return write;
  }
}
