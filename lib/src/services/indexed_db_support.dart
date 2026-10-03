import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<JSAny?> completeIndexedDbRequest(web.IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess = (web.Event _) {
    if (!completer.isCompleted) completer.complete(request.result);
  }.toJS;
  request.onerror = (web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'IndexedDB request failed: ${request.error?.message ?? 'unknown'}',
        ),
      );
    }
  }.toJS;
  return completer.future;
}

class IndexedDbDatabaseHandle {
  IndexedDbDatabaseHandle(
    this._databaseName,
    this._storeNames, {
    this.version = 1,
  });

  final String _databaseName;
  final List<String> _storeNames;
  final int version;

  Future<web.IDBDatabase>? _database;

  Future<web.IDBObjectStore> store(String mode) async {
    final name = _storeNames.single;
    final txn = await transaction([name], mode);
    return txn.objectStore(name);
  }

  Future<web.IDBTransaction> transaction(
    List<String> storeNames,
    String mode,
  ) async {
    final database = await _open();
    final names = [for (final name in storeNames) name.toJS].toJS;
    return database.transaction(names, mode);
  }

  Future<web.IDBDatabase> _open() {
    return _database ??= _openDatabase()
        .onError<Object>((error, _) {
          throw StateError(
            'This browser will not let the app store data locally (private '
            'browsing, or site data turned off). Allow site data for this '
            'site, or use the installed Android, iOS, or desktop app. '
            '[$error]',
          );
        })
        .then(_requireStores)
        .onError<Object>((error, stack) {
          _database = null;
          Error.throwWithStackTrace(error, stack);
        });
  }

  Future<web.IDBDatabase> _openDatabase() async {
    final request = web.window.indexedDB.open(_databaseName, version);
    request.onupgradeneeded = (web.Event _) {
      final database = request.result as web.IDBDatabase;
      for (final name in _storeNames) {
        if (!database.objectStoreNames.contains(name)) {
          database.createObjectStore(name);
        }
      }
    }.toJS;
    return await completeIndexedDbRequest(request) as web.IDBDatabase;
  }

  web.IDBDatabase _requireStores(web.IDBDatabase database) {
    for (final name in _storeNames) {
      if (!database.objectStoreNames.contains(name)) {
        throw StateError(
          'IndexedDB database "$_databaseName" has no object store "$name". '
          "Bump IndexedDbDatabaseHandle's version so onupgradeneeded creates "
          'it.',
        );
      }
    }
    return database;
  }
}
