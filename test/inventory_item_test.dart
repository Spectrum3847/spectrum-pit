import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/inventory_item.dart';

void main() {
  group('InventoryStatus', () {
    test('every value round-trips through name/fromString', () {
      for (final status in InventoryStatus.values) {
        expect(InventoryStatus.fromString(status.name), status);
        expect(InventoryStatus.tryParse(status.name), status);
      }
    });

    test('fromString falls back to inLab for unknown/null values', () {
      expect(InventoryStatus.fromString('garbage'), InventoryStatus.inLab);
      expect(InventoryStatus.fromString(null), InventoryStatus.inLab);
    });

    test('tryParse returns null for unknown values', () {
      expect(InventoryStatus.tryParse('garbage'), isNull);
    });
  });

  group('InventoryItem', () {
    final updatedAt = DateTime.utc(2026, 3, 1, 12, 30);

    InventoryItem buildItem() => InventoryItem(
      id: 'item-1',
      name: 'Impact driver',
      labLocation: 'Shelf A3',
      pitLocation: 'Bin 2',
      mapRef: 'lab#a3',
      status: InventoryStatus.inPit,
      updatedAt: updatedAt,
    );

    test('round trips through toJson/fromJson', () {
      final item = buildItem();
      final json = item.toJson();
      final rebuilt = InventoryItem.fromJson(item.id, json);

      expect(rebuilt.id, item.id);
      expect(rebuilt.name, item.name);
      expect(rebuilt.labLocation, item.labLocation);
      expect(rebuilt.pitLocation, item.pitLocation);
      expect(rebuilt.mapRef, item.mapRef);
      expect(rebuilt.status, item.status);
      expect(rebuilt.updatedAt, item.updatedAt);
    });

    test('omits mapRef from json when null', () {
      final item = InventoryItem(
        id: 'item-2',
        name: 'Wrench',
        labLocation: 'Shelf B1',
        pitLocation: 'Bin 1',
        status: InventoryStatus.inLab,
        updatedAt: updatedAt,
      );

      final json = item.toJson();

      expect(json.containsKey('mapRef'), isFalse);
    });

    test('copyWith changes one field and keeps the rest', () {
      final item = buildItem();
      final copy = item.copyWith(status: InventoryStatus.borrowed);

      expect(copy.status, InventoryStatus.borrowed);
      expect(copy.name, item.name);
      expect(copy.labLocation, item.labLocation);
      expect(copy.pitLocation, item.pitLocation);
      expect(copy.mapRef, item.mapRef);
      expect(copy.updatedAt, item.updatedAt);
    });

    test('copyWith with no args yields an equal-valued copy', () {
      final item = buildItem();
      final copy = item.copyWith();

      expect(copy.id, item.id);
      expect(copy.name, item.name);
      expect(copy.labLocation, item.labLocation);
      expect(copy.pitLocation, item.pitLocation);
      expect(copy.mapRef, item.mapRef);
      expect(copy.status, item.status);
      expect(copy.updatedAt, item.updatedAt);
    });

    test('fromJson tolerates missing fields with documented defaults', () {
      final item = InventoryItem.fromJson('item-3', <String, dynamic>{});

      expect(item.id, 'item-3');
      expect(item.name, '');
      expect(item.labLocation, '');
      expect(item.pitLocation, '');
      expect(item.mapRef, isNull);
      expect(item.status, InventoryStatus.inLab);
      expect(
        item.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });
}
