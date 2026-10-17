import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumpit/src/models/scout_shift_mirror.dart';

void main() {
  group('ScoutShiftMirror.fromJson', () {
    test('round trips through toJson', () {
      final mirror = ScoutShiftMirror(
        eventKey: '2026miket',
        competition: 'Kettering',
        matchCount: 80,
        syncedAt: DateTime.utc(2026, 9, 7, 6, 12),
        rotations: const [
          ScoutRotation(
            uid: 'uid-1',
            name: 'Alex Reyes',
            shifts: [
              MatchRange(startMatch: 1, endMatch: 6),
              MatchRange(startMatch: 13, endMatch: 18),
            ],
          ),
        ],
      );

      final decoded = ScoutShiftMirror.fromJson('2026miket', mirror.toJson());

      expect(decoded.eventKey, '2026miket');
      expect(decoded.competition, 'Kettering');
      expect(decoded.matchCount, 80);
      expect(decoded.syncedAt, DateTime.utc(2026, 9, 7, 6, 12));
      expect(decoded.rotations, hasLength(1));
      expect(decoded.rotations.single.uid, 'uid-1');
      expect(decoded.rotations.single.name, 'Alex Reyes');
      expect(decoded.rotations.single.rangeText, 'Q1-6, Q13-18');
    });

    test('a rotation with no matched uid stays displayable by name', () {
      final mirror = ScoutShiftMirror.fromJson('2026miket', {
        'eventKey': '2026miket',
        'competition': 'Kettering',
        'matchCount': 80,
        'syncedAt': '2026-09-07T06:12:00.000Z',
        'rotations': [
          {
            'name': 'Sam Ito',
            'shifts': [
              {'startMatch': 7, 'endMatch': 12},
            ],
          },
        ],
      });

      final rotation = mirror.rotations.single;
      expect(rotation.uid, isNull);
      expect(rotation.name, 'Sam Ito');
      expect(rotation.rangeText, 'Q7-12');
    });

    test('defaults for missing fields', () {
      final mirror = ScoutShiftMirror.fromJson('2026miket', {});

      expect(mirror.eventKey, '2026miket');
      expect(mirror.competition, '');
      expect(mirror.matchCount, 0);
      expect(mirror.rotations, isEmpty);
    });
  });

  group('MatchRange.label', () {
    test('a single-match range collapses to one match', () {
      const range = MatchRange(startMatch: 7, endMatch: 7);
      expect(range.label, 'Q7');
    });

    test('a multi-match range shows both ends', () {
      const range = MatchRange(startMatch: 1, endMatch: 6);
      expect(range.label, 'Q1-6');
    });
  });
}
