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

    group('contact length (#268)', () {
      BorrowRecord withContact(String? contact) => BorrowRecord(
        id: 'loan-7',
        toolName: 'Drill',
        teamName: 'Radiant Robotics',
        teamNumber: 3847,
        competition: 'Regional Championship',
        contact: contact,
        checkedOutAt: checkedOutAt,
        returned: false,
        updatedAt: updatedAt,
      );

      test('a contact within the limit is untouched', () {
        expect(withContact('555-0100').contact, '555-0100');
        expect(withContact(null).contact, isNull);
        expect(
          withContact('a' * maxBorrowContactLength).contact!.length,
          maxBorrowContactLength,
        );
      });

      test('an overlong contact is clamped to what the rules accept', () {
        final record = withContact('a' * (maxBorrowContactLength + 40));

        expect(record.contact!.length, maxBorrowContactLength);
        expect(
          (record.toJson()['contact'] as String).length,
          maxBorrowContactLength,
        );
      });

      test('an overlong contact read back from Firestore is clamped too', () {
        final record = BorrowRecord.fromJson('loan-8', {
          'toolName': 'Drill',
          'teamName': 'Radiant Robotics',
          'teamNumber': 3847,
          'competition': 'Regional Championship',
          'contact': 'a' * 900,
          'checkedOutAt': checkedOutAt.toIso8601String(),
          'returned': false,
          'updatedAt': updatedAt.toIso8601String(),
        });

        expect(record.contact!.length, maxBorrowContactLength);
      });

      test('clamping never splits a surrogate pair', () {
        final record = withContact('a${'\u{1F600}' * 200}');

        expect(record.contact!.length, maxBorrowContactLength - 1);
        expect(record.contact!.runes.last, 0x1F600);
      });
    });
  });
}
