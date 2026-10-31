class ScoutShiftMirror {
  const ScoutShiftMirror({
    required this.eventKey,
    required this.competition,
    required this.matchCount,
    required this.rotations,
    required this.syncedAt,
  });

  final String eventKey;

  final String competition;

  final int matchCount;
  final List<ScoutRotation> rotations;

  final DateTime syncedAt;

  factory ScoutShiftMirror.fromJson(String id, Map<String, dynamic> data) {
    final rawRotations = data['rotations'];
    return ScoutShiftMirror(
      eventKey: data['eventKey'] as String? ?? id,
      competition: data['competition'] as String? ?? '',
      matchCount: (data['matchCount'] as num?)?.toInt() ?? 0,
      rotations: [
        for (final raw in rawRotations is List ? rawRotations : const [])
          if (raw is Map)
            ScoutRotation.fromJson(Map<String, dynamic>.from(raw)),
      ],
      syncedAt:
          DateTime.tryParse(data['syncedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'eventKey': eventKey,
    'competition': competition,
    'matchCount': matchCount,
    'rotations': [for (final rotation in rotations) rotation.toJson()],
    'syncedAt': syncedAt.toIso8601String(),
  };
}

class ScoutRotation {
  const ScoutRotation({
    required this.uid,
    required this.name,
    required this.shifts,
  });

  final String? uid;

  final String name;
  final List<MatchRange> shifts;

  factory ScoutRotation.fromJson(Map<String, dynamic> data) {
    final rawShifts = data['shifts'];
    return ScoutRotation(
      uid: data['uid'] as String?,
      name: data['name'] as String? ?? '',
      shifts: [
        for (final raw in rawShifts is List ? rawShifts : const [])
          if (raw is Map) MatchRange.fromJson(Map<String, dynamic>.from(raw)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    if (uid != null) 'uid': uid,
    'name': name,
    'shifts': [for (final range in shifts) range.toJson()],
  };

  String get rangeText => shifts.map((r) => r.label).join(', ');
}

class MatchRange {
  const MatchRange({required this.startMatch, required this.endMatch});

  final int startMatch;
  final int endMatch;

  factory MatchRange.fromJson(Map<String, dynamic> data) => MatchRange(
    startMatch: (data['startMatch'] as num?)?.toInt() ?? 0,
    endMatch: (data['endMatch'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'startMatch': startMatch,
    'endMatch': endMatch,
  };

  String get label =>
      startMatch == endMatch ? 'Q$startMatch' : 'Q$startMatch-$endMatch';
}
