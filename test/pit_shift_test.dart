import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/pit_shift.dart';

PitShift _shift(
  String id, {
  String label = 'Shift',
  ShiftKind kind = ShiftKind.pitDuty,
  String competition = 'Houston',
  List<String> assignedUids = const ['uid-1'],
  int? startMatch,
  int? endMatch,
  DateTime? startsAt,
  DateTime? endsAt,
}) => PitShift(
  id: id,
  label: label,
  kind: kind,
  competition: competition,
  assignedUids: assignedUids,
  assignedNames: const ['Tester'],
  startMatch: startMatch,
  endMatch: endMatch,
  startsAt: startsAt,
  endsAt: endsAt,
  updatedAt: DateTime.utc(2026, 1, 1),
);

DateTime _at(int hour) => DateTime.utc(2026, 4, 10, hour);

void main() {
  group('PitShift.fromJson', () {
    test('parses a complete document', () {
      final shift = PitShift.fromJson('shift-1', {
        'label': 'Load in',
        'kind': 'loadIn',
        'competition': 'Houston',
        'assignedUids': ['uid-1', 'uid-2'],
        'assignedNames': ['Ana', 'Ben'],
        'startMatch': 1,
        'endMatch': 20,
        'startsAt': '2026-04-10T08:00:00.000Z',
        'endsAt': '2026-04-10T10:00:00.000Z',
        'notes': 'Meet at the dock',
        'updatedAt': '2026-04-01T00:00:00.000Z',
      });
      expect(shift.id, 'shift-1');
      expect(shift.label, 'Load in');
      expect(shift.kind, ShiftKind.loadIn);
      expect(shift.competition, 'Houston');
      expect(shift.assignedUids, ['uid-1', 'uid-2']);
      expect(shift.assignedNames, ['Ana', 'Ben']);
      expect(shift.startMatch, 1);
      expect(shift.endMatch, 20);
      expect(shift.startsAt, DateTime.utc(2026, 4, 10, 8));
      expect(shift.endsAt, DateTime.utc(2026, 4, 10, 10));
      expect(shift.notes, 'Meet at the dock');
    });

    test('defaults for missing fields', () {
      final shift = PitShift.fromJson('x', {});
      expect(shift.label, '');
      expect(shift.kind, ShiftKind.pitDuty);
      expect(shift.competition, '');
      expect(shift.assignedUids, isEmpty);
      expect(shift.assignedNames, isEmpty);
      expect(shift.startMatch, isNull);
      expect(shift.endMatch, isNull);
      expect(shift.startsAt, isNull);
      expect(shift.endsAt, isNull);
      expect(shift.notes, isNull);

      expect(
        shift.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('drops non-string entries from the assignment lists', () {
      final shift = PitShift.fromJson('x', {
        'assignedUids': ['uid-1', 7, null],
        'assignedNames': 'not a list',
      });
      expect(shift.assignedUids, ['uid-1']);
      expect(shift.assignedNames, isEmpty);
    });
  });

  group('PitShift.toJson', () {
    test('roundtrips through fromJson', () {
      final original = PitShift(
        id: 'shift-2',
        label: 'Match block',
        kind: ShiftKind.matchBlock,
        competition: 'Worlds',
        assignedUids: const ['uid-3'],
        assignedNames: const ['Cass'],
        startMatch: 30,
        endMatch: 45,
        startsAt: DateTime.utc(2026, 4, 10, 8),
        endsAt: DateTime.utc(2026, 4, 10, 12),
        notes: 'Queue early',
        updatedAt: DateTime.utc(2026, 3, 15),
      );
      final restored = PitShift.fromJson('shift-2', original.toJson());
      expect(restored.label, original.label);
      expect(restored.kind, original.kind);
      expect(restored.competition, original.competition);
      expect(restored.assignedUids, original.assignedUids);
      expect(restored.assignedNames, original.assignedNames);
      expect(restored.startMatch, original.startMatch);
      expect(restored.endMatch, original.endMatch);
      expect(restored.startsAt, original.startsAt);
      expect(restored.endsAt, original.endsAt);
      expect(restored.notes, original.notes);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('omits the null optionals', () {
      final json = _shift('a').toJson();
      expect(json, isNot(contains('startMatch')));
      expect(json, isNot(contains('endMatch')));
      expect(json, isNot(contains('startsAt')));
      expect(json, isNot(contains('endsAt')));
      expect(json, isNot(contains('notes')));
    });

    test('never writes the document id', () {
      expect(_shift('a').toJson(), isNot(contains('id')));
    });
  });

  group('ShiftKind', () {
    test('fromString parses known values', () {
      expect(ShiftKind.fromString('loadIn'), ShiftKind.loadIn);
      expect(ShiftKind.fromString('matchBlock'), ShiftKind.matchBlock);
      expect(ShiftKind.fromString('pitDuty'), ShiftKind.pitDuty);
      expect(ShiftKind.fromString('loadOut'), ShiftKind.loadOut);
      expect(ShiftKind.fromString('unavailable'), ShiftKind.unavailable);
    });

    test('fromString falls back to pitDuty for unknown', () {
      expect(ShiftKind.fromString('lunch'), ShiftKind.pitDuty);
      expect(ShiftKind.fromString(null), ShiftKind.pitDuty);
    });

    test('tryParse returns null for unknown', () {
      expect(ShiftKind.tryParse('lunch'), isNull);
      expect(ShiftKind.tryParse(null), isNull);
    });
  });

  group('PitShift.copyWith', () {
    test('preserves unmodified fields', () {
      final original = _shift('s1', label: 'Original', startMatch: 5);
      final updated = original.copyWith(label: 'Renamed');
      expect(updated.id, 's1');
      expect(updated.label, 'Renamed');
      expect(updated.kind, original.kind);
      expect(updated.competition, original.competition);
      expect(updated.assignedUids, original.assignedUids);
      expect(updated.startMatch, 5);
    });
  });

  group('PitShift.conflictsWith', () {
    test('overlapping match ranges for a shared assignee conflict', () {
      final a = _shift('a', startMatch: 1, endMatch: 20);
      final b = _shift('b', startMatch: 15, endMatch: 30);
      expect(a.conflictsWith(b), isTrue);
      expect(b.conflictsWith(a), isTrue);
    });

    test('match ranges that only touch still conflict (inclusive)', () {
      final a = _shift('a', startMatch: 1, endMatch: 20);
      final b = _shift('b', startMatch: 20, endMatch: 30);
      expect(a.conflictsWith(b), isTrue);
    });

    test('disjoint match ranges do not conflict', () {
      final a = _shift('a', startMatch: 1, endMatch: 19);
      final b = _shift('b', startMatch: 20, endMatch: 30);
      expect(a.conflictsWith(b), isFalse);
    });

    test('overlapping time ranges for a shared assignee conflict', () {
      final a = _shift('a', startsAt: _at(8), endsAt: _at(12));
      final b = _shift('b', startsAt: _at(11), endsAt: _at(14));
      expect(a.conflictsWith(b), isTrue);
    });

    test('touching time endpoints do not conflict (half-open)', () {
      final a = _shift('a', startsAt: _at(8), endsAt: _at(12));
      final b = _shift('b', startsAt: _at(12), endsAt: _at(16));
      expect(a.conflictsWith(b), isFalse);
      expect(b.conflictsWith(a), isFalse);
    });

    test('a match range and a time range are not comparable', () {
      final a = _shift('a', startMatch: 1, endMatch: 20);
      final b = _shift('b', startsAt: _at(8), endsAt: _at(12));
      expect(a.conflictsWith(b), isFalse);
      expect(b.conflictsWith(a), isFalse);
    });

    test('a shift with no range conflicts with nothing', () {
      final bare = _shift('a');
      expect(
        bare.conflictsWith(_shift('b', startMatch: 1, endMatch: 20)),
        isFalse,
      );
      expect(
        bare.conflictsWith(_shift('c', startsAt: _at(8), endsAt: _at(9))),
        isFalse,
      );
      expect(bare.conflictsWith(_shift('d')), isFalse);
    });

    test('an open-ended match range extends forever', () {
      final open = _shift('a', startMatch: 40);
      expect(
        open.conflictsWith(_shift('b', startMatch: 60, endMatch: 70)),
        isTrue,
      );
      expect(
        open.conflictsWith(_shift('c', startMatch: 1, endMatch: 39)),
        isFalse,
      );
    });

    test('a match range with only an end extends backwards forever', () {
      final open = _shift('a', endMatch: 10);
      expect(
        open.conflictsWith(_shift('b', startMatch: 1, endMatch: 5)),
        isTrue,
      );
      expect(
        open.conflictsWith(_shift('c', startMatch: 11, endMatch: 20)),
        isFalse,
      );
    });

    test('an open-ended time range extends forever', () {
      final open = _shift('a', startsAt: _at(12));
      expect(
        open.conflictsWith(_shift('b', startsAt: _at(20), endsAt: _at(22))),
        isTrue,
      );
      expect(
        open.conflictsWith(_shift('c', startsAt: _at(8), endsAt: _at(12))),
        isFalse,
      );
    });

    test('a time range with only an end extends backwards forever', () {
      final open = _shift('a', endsAt: _at(12));
      expect(
        open.conflictsWith(_shift('b', startsAt: _at(8), endsAt: _at(9))),
        isTrue,
      );
      expect(
        open.conflictsWith(_shift('c', startsAt: _at(12), endsAt: _at(14))),
        isFalse,
      );
    });

    test('two half-open match ranges conflict where they meet', () {
      expect(
        _shift('a', startMatch: 5).conflictsWith(_shift('b', endMatch: 7)),
        isTrue,
      );
      expect(
        _shift('a', startMatch: 5).conflictsWith(_shift('b', endMatch: 3)),
        isFalse,
      );
    });

    test('no shared assignee means no conflict', () {
      final a = _shift('a', startMatch: 1, endMatch: 20);
      final b = _shift(
        'b',
        assignedUids: const ['uid-2'],
        startMatch: 1,
        endMatch: 20,
      );
      expect(a.conflictsWith(b), isFalse);
    });

    test('different competitions never conflict', () {
      final a = _shift('a', startMatch: 1, endMatch: 20);
      final b = _shift('b', competition: 'Worlds', startMatch: 1, endMatch: 20);
      expect(a.conflictsWith(b), isFalse);
    });

    test('a shift never conflicts with itself', () {
      final a = _shift('a', startMatch: 1, endMatch: 20);
      expect(a.conflictsWith(a), isFalse);

      expect(a.conflictsWith(a.copyWith(label: 'Edited')), isFalse);
    });

    test('an unavailable block conflicts with an assignment', () {
      final duty = _shift('a', startsAt: _at(8), endsAt: _at(12));
      final away = _shift(
        'b',
        kind: ShiftKind.unavailable,
        startsAt: _at(10),
        endsAt: _at(14),
      );
      expect(duty.conflictsWith(away), isTrue);
    });

    test('an inverted match range still conflicts through its edges', () {
      final inverted = _shift('a', startMatch: 20, endMatch: 5);
      expect(
        inverted.conflictsWith(_shift('b', startMatch: 1, endMatch: 30)),
        isTrue,
      );
      expect(
        inverted.conflictsWith(_shift('c', startMatch: 10, endMatch: 15)),
        isFalse,
      );
      expect(
        inverted.conflictsWith(_shift('d', startMatch: 1, endMatch: 5)),
        isFalse,
      );
      expect(
        inverted.conflictsWith(_shift('e', startMatch: 20, endMatch: 30)),
        isFalse,
      );
    });

    test('two unavailable blocks for the same person do not conflict', () {
      final a = _shift(
        'a',
        kind: ShiftKind.unavailable,
        startMatch: 1,
        endMatch: 20,
      );
      final b = _shift(
        'b',
        kind: ShiftKind.unavailable,
        startMatch: 10,
        endMatch: 30,
      );
      expect(a.conflictsWith(b), isFalse);
    });
  });

  group('findPitShiftConflicts', () {
    test('reports each conflicting pair once', () {
      final a = _shift('a', startMatch: 1, endMatch: 20);
      final b = _shift('b', startMatch: 15, endMatch: 30);
      final c = _shift('c', startMatch: 40, endMatch: 50);
      final conflicts = findPitShiftConflicts([a, b, c]);
      expect(conflicts.length, 1);
      expect(conflicts.single.first.id, 'a');
      expect(conflicts.single.second.id, 'b');
    });

    test('is empty for a clean schedule', () {
      expect(
        findPitShiftConflicts([
          _shift('a', startMatch: 1, endMatch: 19),
          _shift('b', startMatch: 20, endMatch: 30),
        ]),
        isEmpty,
      );
    });
  });
}
