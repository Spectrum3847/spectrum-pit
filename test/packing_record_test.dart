import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/packing_record.dart';

void main() {
  group('PackingStatus', () {
    test('every value round-trips through name/fromString', () {
      for (final status in PackingStatus.values) {
        expect(PackingStatus.fromString(status.name), status);
        expect(PackingStatus.tryParse(status.name), status);
      }
    });

    test('fromString falls back to packing for unknown/null values', () {
      expect(PackingStatus.fromString('garbage'), PackingStatus.packing);
      expect(PackingStatus.fromString(null), PackingStatus.packing);
    });

    test('fromString parses notStarted explicitly', () {
      expect(PackingStatus.fromString('notStarted'), PackingStatus.notStarted);
      expect(PackingStatus.tryParse('notStarted'), PackingStatus.notStarted);
    });

    test('tryParse returns null for unknown values', () {
      expect(PackingStatus.tryParse('garbage'), isNull);
    });
  });

  group('PackingRecord', () {
    final updatedAt = DateTime.utc(2026, 3, 2, 8, 15);

    PackingRecord buildRecord() => PackingRecord(
      id: 'record-1',
      itemId: 'item-1',
      packingStatus: PackingStatus.staging,
      photoRef: 'photos/record-1.jpg',
      updatedAt: updatedAt,
    );

    test('round trips through toJson/fromJson', () {
      final record = buildRecord();
      final json = record.toJson();
      final rebuilt = PackingRecord.fromJson(record.id, json);

      expect(rebuilt.id, record.id);
      expect(rebuilt.itemId, record.itemId);
      expect(rebuilt.packingStatus, record.packingStatus);
      expect(rebuilt.photoRef, record.photoRef);
      expect(rebuilt.updatedAt, record.updatedAt);
    });

    test('omits photoRef from json when null', () {
      final record = PackingRecord(
        id: 'record-2',
        itemId: 'item-2',
        packingStatus: PackingStatus.packing,
        updatedAt: updatedAt,
      );

      final json = record.toJson();

      expect(json.containsKey('photoRef'), isFalse);
    });

    test('copyWith changes one field and keeps the rest', () {
      final record = buildRecord();
      final copy = record.copyWith(packingStatus: PackingStatus.ready);

      expect(copy.packingStatus, PackingStatus.ready);
      expect(copy.itemId, record.itemId);
      expect(copy.photoRef, record.photoRef);
      expect(copy.updatedAt, record.updatedAt);
    });

    test('copyWith with no args yields an equal-valued copy', () {
      final record = buildRecord();
      final copy = record.copyWith();

      expect(copy.id, record.id);
      expect(copy.itemId, record.itemId);
      expect(copy.packingStatus, record.packingStatus);
      expect(copy.photoRef, record.photoRef);
      expect(copy.updatedAt, record.updatedAt);
    });

    test('fromJson tolerates missing fields with documented defaults', () {
      final record = PackingRecord.fromJson('record-3', <String, dynamic>{});

      expect(record.id, 'record-3');
      expect(record.itemId, '');
      expect(record.packingStatus, PackingStatus.packing);
      expect(record.photoRef, isNull);
      expect(
        record.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });
}
