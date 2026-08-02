import 'pit_model.dart';

class PitShift implements PitModel {
  const PitShift({
    required this.id,
    required this.label,
    required this.kind,
    required this.competition,
    required this.assignedUids,
    required this.assignedNames,
    this.startMatch,
    this.endMatch,
    this.startsAt,
    this.endsAt,
    this.notes,
    required this.updatedAt,
  });

  @override
  final String id;
  final String label;
  final ShiftKind kind;
  final String competition;
  final List<String> assignedUids;

  final List<String> assignedNames;

  final int? startMatch;
  final int? endMatch;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? notes;
  final DateTime updatedAt;

  bool get hasMatchRange => startMatch != null || endMatch != null;

  bool get hasTimeRange => startsAt != null || endsAt != null;

  bool conflictsWith(PitShift other) {
    if (other.id == id) return false;
    if (other.competition != competition) return false;
    if (!assignedUids.any(other.assignedUids.contains)) return false;

    if (kind == ShiftKind.unavailable && other.kind == ShiftKind.unavailable) {
      return false;
    }
    if (hasMatchRange && other.hasMatchRange && _matchesOverlap(other)) {
      return true;
    }
    return hasTimeRange && other.hasTimeRange && _timesOverlap(other);
  }

  bool _matchesOverlap(PitShift other) {
    final startsBeforeOtherEnds =
        startMatch == null ||
        other.endMatch == null ||
        startMatch! <= other.endMatch!;
    final otherStartsBeforeThisEnds =
        other.startMatch == null ||
        endMatch == null ||
        other.startMatch! <= endMatch!;
    return startsBeforeOtherEnds && otherStartsBeforeThisEnds;
  }

  bool _timesOverlap(PitShift other) {
    final startsBeforeOtherEnds =
        startsAt == null ||
        other.endsAt == null ||
        startsAt!.isBefore(other.endsAt!);
    final otherStartsBeforeThisEnds =
        other.startsAt == null ||
        endsAt == null ||
        other.startsAt!.isBefore(endsAt!);
    return startsBeforeOtherEnds && otherStartsBeforeThisEnds;
  }

  factory PitShift.fromJson(String id, Map<String, dynamic> data) {
    final startsAtRaw = data['startsAt'] as String?;
    final endsAtRaw = data['endsAt'] as String?;
    return PitShift(
      id: id,
      label: data['label'] as String? ?? '',
      kind: ShiftKind.fromString(data['kind'] as String?),
      competition: data['competition'] as String? ?? '',
      assignedUids: _stringList(data['assignedUids']),
      assignedNames: _stringList(data['assignedNames']),
      startMatch: (data['startMatch'] as num?)?.toInt(),
      endMatch: (data['endMatch'] as num?)?.toInt(),
      startsAt: startsAtRaw == null ? null : DateTime.tryParse(startsAtRaw),
      endsAt: endsAtRaw == null ? null : DateTime.tryParse(endsAtRaw),
      notes: data['notes'] as String?,
      updatedAt:
          DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  @override
  Map<String, dynamic> toJson() => {
    'label': label,
    'kind': kind.name,
    'competition': competition,
    'assignedUids': assignedUids,
    'assignedNames': assignedNames,
    if (startMatch != null) 'startMatch': startMatch,
    if (endMatch != null) 'endMatch': endMatch,
    if (startsAt != null) 'startsAt': startsAt!.toIso8601String(),
    if (endsAt != null) 'endsAt': endsAt!.toIso8601String(),
    if (notes != null) 'notes': notes,
    'updatedAt': updatedAt.toIso8601String(),
  };

  PitShift copyWith({
    String? label,
    ShiftKind? kind,
    String? competition,
    List<String>? assignedUids,
    List<String>? assignedNames,
    int? startMatch,
    int? endMatch,
    DateTime? startsAt,
    DateTime? endsAt,
    String? notes,
    DateTime? updatedAt,
  }) {
    return PitShift(
      id: id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      competition: competition ?? this.competition,
      assignedUids: assignedUids ?? this.assignedUids,
      assignedNames: assignedNames ?? this.assignedNames,
      startMatch: startMatch ?? this.startMatch,
      endMatch: endMatch ?? this.endMatch,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      notes: notes ?? this.notes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

typedef PitShiftConflict = ({PitShift first, PitShift second});

List<PitShiftConflict> findPitShiftConflicts(List<PitShift> shifts) {
  final conflicts = <PitShiftConflict>[];
  for (var i = 0; i < shifts.length; i++) {
    for (var j = i + 1; j < shifts.length; j++) {
      if (shifts[i].conflictsWith(shifts[j])) {
        conflicts.add((first: shifts[i], second: shifts[j]));
      }
    }
  }
  return conflicts;
}

enum ShiftKind {
  loadIn,
  matchBlock,
  pitDuty,
  loadOut,
  unavailable;

  static final Map<String, ShiftKind> _byName = {
    for (final kind in ShiftKind.values) kind.name: kind,
  };

  static ShiftKind fromString(String? value) =>
      tryParse(value) ?? ShiftKind.pitDuty;

  static ShiftKind? tryParse(String? value) =>
      value == null ? null : _byName[value];
}
