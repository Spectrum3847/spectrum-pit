import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';

abstract class InventorySyncService {
  Future<List<InventoryItem>> fetchAll();

  Future<void> upsert(InventoryItem item);

  Future<void> delete(String id);

  Stream<List<InventoryItem>> streamAll();
}

class FirestoreInventorySyncService implements InventorySyncService {
  FirestoreInventorySyncService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('inventoryItems');

  @override
  Future<List<InventoryItem>> fetchAll() async {
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
        debugPrint('inventoryItems server fetch failed: $serverError');
        debugPrint('inventoryItems cache fetch failed: $cacheError');
        return const <InventoryItem>[];
      }
    }
  }

  @override
  Future<void> upsert(InventoryItem item) =>
      _collection.doc(item.id).set(item.toJson());

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();

  @override
  Stream<List<InventoryItem>> streamAll() =>
      _collection.snapshots().map(_itemsFrom);

  List<InventoryItem> _itemsFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => snapshot.docs
      .map((doc) => InventoryItem.fromJson(doc.id, doc.data()))
      .toList();
}

class LocalInventorySyncService implements InventorySyncService {
  @override
  Future<List<InventoryItem>> fetchAll() async => const <InventoryItem>[];

  @override
  Future<void> upsert(InventoryItem item) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Stream<List<InventoryItem>> streamAll() =>
      const Stream<List<InventoryItem>>.empty();
}
