import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/borrow_record.dart';

void main() {
  group('BorrowRecord', () {
    final checkedOutAt = DateTime.utc(2026, 3, 1, 9, 0);
    final estimatedReturn = DateTime.utc(2026, 3, 1, 11, 0);
    final checkedInAt = DateTime.utc(2026, 3, 1, 10, 45);
    final updatedAt = DateTime.utc(2026, 3, 1, 10, 45);

    BorrowRecord buildRecord() => BorrowRecord(
      id: 'loan-1',
      itemId: 'item-1',
      toolName: 'Cordless drill',
      teamName: 'Radiant Robotics',
      teamNumber: 3847,
      competition: 'Regional Championship',
      contact: '555-0100',
      checkedOutAt: checkedOutAt,
      estimatedReturn: estimatedReturn,
      checkedInAt: checkedInAt,
      returned: true,
      updatedAt: updatedAt,
    );

    test('round trips through toJson/fromJson', () {
      final record = buildRecord();
      final json = record.toJson();
      final rebuilt = BorrowRecord.fromJson(record.id, json);

      expect(rebuilt.id, record.id);
      expect(rebuilt.itemId, record.itemId);
      expect(rebuilt.toolName, record.toolName);
      expect(rebuilt.teamName, record.teamName);
      expect(rebuilt.teamNumber, record.teamNumber);
      expect(rebuilt.competition, record.competition);
      expect(rebuilt.contact, record.contact);
      expect(rebuilt.checkedOutAt, record.checkedOutAt);
      expect(rebuilt.estimatedReturn, record.estimatedReturn);
      expect(rebuilt.checkedInAt, record.checkedInAt);
      expect(rebuilt.returned, record.returned);
      expect(rebuilt.updatedAt, record.updatedAt);
    });

    test('omits itemId, contact, estimatedReturn and checkedInAt from json '
        'when null', () {
      final record = BorrowRecord(
        id: 'loan-2',
        toolName: 'Tape measure',
        teamName: 'Radiant Robotics',
        teamNumber: 3847,
        competition: 'Regional Championship',
        checkedOutAt: checkedOutAt,
        returned: false,
        updatedAt: updatedAt,
      );

      final json = record.toJson();

      expect(json.containsKey('itemId'), isFalse);
      expect(json.containsKey('contact'), isFalse);
      expect(json.containsKey('estimatedReturn'), isFalse);
      expect(json.containsKey('checkedInAt'), isFalse);
    });

    test('copyWith changes one field and keeps the rest', () {
      final record = buildRecord();
      final copy = record.copyWith(returned: false);

      expect(copy.returned, isFalse);
      expect(copy.toolName, record.toolName);
      expect(copy.teamName, record.teamName);
      expect(copy.teamNumber, record.teamNumber);
      expect(copy.competition, record.competition);
      expect(copy.contact, record.contact);
      expect(copy.checkedOutAt, record.checkedOutAt);
      expect(copy.estimatedReturn, record.estimatedReturn);
      expect(copy.checkedInAt, record.checkedInAt);
      expect(copy.updatedAt, record.updatedAt);
    });

    test('copyWith with no args yields an equal-valued copy', () {
      final record = buildRecord();
      final copy = record.copyWith();

      expect(copy.id, record.id);
      expect(copy.itemId, record.itemId);
      expect(copy.toolName, record.toolName);
      expect(copy.teamName, record.teamName);
      expect(copy.teamNumber, record.teamNumber);
      expect(copy.competition, record.competition);
      expect(copy.contact, record.contact);
      expect(copy.checkedOutAt, record.checkedOutAt);
      expect(copy.estimatedReturn, record.estimatedReturn);
      expect(copy.checkedInAt, record.checkedInAt);
      expect(copy.returned, record.returned);
      expect(copy.updatedAt, record.updatedAt);
    });

    test('fromJson tolerates missing fields with documented defaults', () {
      final record = BorrowRecord.fromJson('loan-3', <String, dynamic>{});

      expect(record.id, 'loan-3');
      expect(record.itemId, isNull);
      expect(record.toolName, '');
      expect(record.teamName, '');
      expect(record.teamNumber, 0);
      expect(record.competition, '');
      expect(record.contact, isNull);
      expect(
        record.checkedOutAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(record.estimatedReturn, isNull);
      expect(record.checkedInAt, isNull);
      expect(record.returned, isFalse);
      expect(
        record.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    group('isOverdueAt', () {
      test('true when now is after estimatedReturn and not returned', () {
        final record = BorrowRecord(
          id: 'loan-4',
          toolName: 'Drill',
          teamName: 'Radiant Robotics',
          teamNumber: 3847,
          competition: 'Regional Championship',
          checkedOutAt: checkedOutAt,
          estimatedReturn: estimatedReturn,
          returned: false,
          updatedAt: updatedAt,
        );

        expect(
          record.isOverdueAt(estimatedReturn.add(const Duration(minutes: 1))),
          isTrue,
        );
      });

      test('false when returned even if past estimatedReturn', () {
        final record = BorrowRecord(
          id: 'loan-5',
          toolName: 'Drill',
          teamName: 'Radiant Robotics',
          teamNumber: 3847,
          competition: 'Regional Championship',
          checkedOutAt: checkedOutAt,
          estimatedReturn: estimatedReturn,
          returned: true,
          updatedAt: updatedAt,
        );

        expect(
          record.isOverdueAt(estimatedReturn.add(const Duration(minutes: 1))),
          isFalse,
        );
      });

      test('false when estimatedReturn is null', () {
        final record = BorrowRecord(
          id: 'loan-6',
          toolName: 'Drill',
          teamName: 'Radiant Robotics',
          teamNumber: 3847,
          competition: 'Regional Championship',
          checkedOutAt: checkedOutAt,
          returned: false,
          updatedAt: updatedAt,
        );

        expect(record.isOverdueAt(DateTime.utc(2030, 1, 1)), isFalse);
      });
    });
  });
}
