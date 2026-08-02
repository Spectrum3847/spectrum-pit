import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/map_location.dart';

abstract class MapLocationSyncService {
  Future<List<MapLocation>> fetchAll();
  Future<void> upsert(MapLocation location);
  Future<void> delete(String id);
  Stream<List<MapLocation>> streamAll();
}

class FirestoreMapLocationSyncService implements MapLocationSyncService {
  FirestoreMapLocationSyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('mapLocations');

  @override
  Future<List<MapLocation>> fetchAll() async {
    try {
      final snapshot = await _collection.get();
      return _itemsFrom(snapshot);
    } catch (serverError) {
      try {
        final cached = await _collection.get(
          const GetOptions(source: Source.cache),
        );
        return _itemsFrom(cached);
      } catch (cacheError) {
        debugPrint('mapLocations server fetch failed: $serverError');
        debugPrint('mapLocations cache fetch failed: $cacheError');
        return const <MapLocation>[];
      }
    }
  }

  @override
  Future<void> upsert(MapLocation location) =>
      _collection.doc(location.id).set(location.toJson());

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();

  @override
  Stream<List<MapLocation>> streamAll() =>
      _collection.snapshots().map(_itemsFrom);

  List<MapLocation> _itemsFrom(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs
          .map((doc) => MapLocation.fromJson(doc.id, doc.data()))
          .toList();
}

class LocalMapLocationSyncService implements MapLocationSyncService {
  @override
  Future<List<MapLocation>> fetchAll() async => const <MapLocation>[];

  @override
  Future<void> upsert(MapLocation location) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Stream<List<MapLocation>> streamAll() =>
      const Stream<List<MapLocation>>.empty();
}
