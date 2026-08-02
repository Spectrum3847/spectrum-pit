import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/map_location.dart';

void main() {
  group('MapLocation.fromJson', () {
    test('parses a complete document', () {
      final loc = MapLocation.fromJson('pin-1', {
        'name': 'Cabinet A',
        'mapType': 'lab',
        'x': 0.5,
        'y': 0.3,
        'inventoryItemId': 'inv-1',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(loc.id, 'pin-1');
      expect(loc.name, 'Cabinet A');
      expect(loc.mapType, MapType.lab);
      expect(loc.x, 0.5);
      expect(loc.y, 0.3);
      expect(loc.inventoryItemId, 'inv-1');
    });

    test('defaults for missing fields', () {
      final loc = MapLocation.fromJson('x', {});
      expect(loc.name, '');
      expect(loc.mapType, MapType.lab);
      expect(loc.x, 0);
      expect(loc.y, 0);
      expect(loc.inventoryItemId, isNull);
    });
  });

  group('MapLocation.toJson', () {
    test('roundtrips through fromJson', () {
      final original = MapLocation(
        id: 'pin-2',
        name: 'Road Case 1',
        mapType: MapType.pit,
        x: 0.7,
        y: 0.2,
        inventoryItemId: 'inv-3',
        updatedAt: DateTime.utc(2026, 3, 15),
      );
      final json = original.toJson();
      final restored = MapLocation.fromJson('pin-2', json);
      expect(restored.name, original.name);
      expect(restored.mapType, original.mapType);
      expect(restored.x, original.x);
      expect(restored.y, original.y);
      expect(restored.inventoryItemId, original.inventoryItemId);
    });

    test('omits null inventoryItemId', () {
      final loc = MapLocation(
        id: 'a',
        name: 'Bare',
        mapType: MapType.lab,
        x: 0,
        y: 0,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(loc.toJson(), isNot(contains('inventoryItemId')));
    });
  });

  group('MapType', () {
    test('fromString parses known values', () {
      expect(MapType.fromString('lab'), MapType.lab);
      expect(MapType.fromString('pit'), MapType.pit);
    });

    test('fromString falls back to lab for unknown', () {
      expect(MapType.fromString('garage'), MapType.lab);
      expect(MapType.fromString(null), MapType.lab);
    });

    test('tryParse returns null for unknown', () {
      expect(MapType.tryParse('garage'), isNull);
      expect(MapType.tryParse(null), isNull);
    });
  });

  group('MapLocation.copyWith', () {
    test('preserves unmodified fields', () {
      final original = MapLocation(
        id: 'p1',
        name: 'Cabinet',
        mapType: MapType.lab,
        x: 0.1,
        y: 0.2,
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final updated = original.copyWith(name: 'New Name');
      expect(updated.id, 'p1');
      expect(updated.name, 'New Name');
      expect(updated.mapType, MapType.lab);
      expect(updated.x, 0.1);
      expect(updated.y, 0.2);
    });
  });
}
