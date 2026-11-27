import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumpit/src/models/pit_shift.dart';

void main() {
  final now = DateTime.utc(2026, 8, 14, 12);

  PitShift shift({String? importedFrom, List<String>? uids}) => PitShift(
    id: 's1',
    label: 'Drive team, match 1',
    kind: ShiftKind.matchBlock,
    competition: 'Houston',
    assignedUids: uids ?? const ['uid-1'],
    assignedNames: const ['Someone'],
    startMatch: 1,
    endMatch: 1,
    importedFrom: importedFrom,
    updatedAt: now,
  );

  group('importedFrom', () {
    test('is absent on a hand-made shift, which is the normal case', () {
      final hand = shift();

      expect(hand.importedFrom, isNull);
      expect(hand.isImported, isFalse);
      expect(hand.toJson().containsKey('importedFrom'), isFalse);
    });

    test('survives a round trip', () {
      final json = shift(importedFrom: PitShift.driverScheduleImport).toJson();

      final back = PitShift.fromJson('s1', json);
      expect(back.importedFrom, PitShift.driverScheduleImport);
      expect(back.isImported, isTrue);
    });

    test('a document written before the field existed still decodes', () {
      final legacy = shift().toJson()..remove('importedFrom');

      expect(PitShift.fromJson('s1', legacy).importedFrom, isNull);
    });

    test('copyWith carries it', () {
      final imported = shift(importedFrom: PitShift.driverScheduleImport);

      expect(
        imported.copyWith(label: 'renamed').importedFrom,
        PitShift.driverScheduleImport,
      );
    });
  });

  group('the stand-in uid', () {
    test('is stable for the same person however the name was typed', () {
      expect(
        PitShift.unlinkedUid('Ada Lovelace'),
        PitShift.unlinkedUid('  ada lovelace  '),
      );
    });

    test('differs between two people', () {
      expect(PitShift.unlinkedUid('Ada'), isNot(PitShift.unlinkedUid('Grace')));
    });

    test('cannot be mistaken for a real Firebase uid', () {
      expect(
        PitShift.unlinkedUid('Ada'),
        startsWith(PitShift.unlinkedUidPrefix),
      );
      expect(PitShift.unlinkedUid('Ada'), contains(':'));
    });

    test('flags a shift that has one', () {
      expect(
        shift(uids: [PitShift.unlinkedUid('Ada')]).hasUnlinkedAssignees,
        isTrue,
      );
      expect(shift(uids: const ['a-real-uid']).hasUnlinkedAssignees, isFalse);
    });

    test('flags a shift where only some people are unlinked', () {
      final mixed = shift(uids: ['a-real-uid', PitShift.unlinkedUid('Ada')]);

      expect(mixed.hasUnlinkedAssignees, isTrue);
    });

    test('still pairs the same person with themselves for conflicts', () {
      final ada = PitShift.unlinkedUid('Ada');
      final driveTeam = shift(uids: [ada]);
      final pitDuty = PitShift(
        id: 's2',
        label: 'Pit duty, match 1',
        kind: ShiftKind.pitDuty,
        competition: 'Houston',
        assignedUids: [ada],
        assignedNames: const ['Ada'],
        startMatch: 1,
        endMatch: 1,
        updatedAt: now,
      );

      expect(driveTeam.conflictsWith(pitDuty), isTrue);
    });

    test('two different unlinked people do not conflict', () {
      final ada = shift(uids: [PitShift.unlinkedUid('Ada')]);
      final grace = PitShift(
        id: 's2',
        label: 'Pit duty, match 1',
        kind: ShiftKind.pitDuty,
        competition: 'Houston',
        assignedUids: [PitShift.unlinkedUid('Grace')],
        assignedNames: const ['Grace'],
        startMatch: 1,
        endMatch: 1,
        updatedAt: now,
      );

      expect(ada.conflictsWith(grace), isFalse);
    });
  });
}
