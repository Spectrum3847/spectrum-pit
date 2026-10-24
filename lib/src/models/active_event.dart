class ActiveEvent {
  const ActiveEvent({
    required this.eventKey,
    required this.eventName,
    required this.updatedAt,
  });

  final String eventKey;

  final String eventName;

  final DateTime updatedAt;

  static ActiveEvent? fromJson(Map<String, dynamic>? data) {
    final key = data?['eventKey'];
    if (key is! String || key.isEmpty) return null;
    final name = data?['eventName'];
    return ActiveEvent(
      eventKey: key,
      eventName: name is String ? name : '',
      updatedAt:
          DateTime.tryParse(data?['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'eventKey': eventKey,
    'eventName': eventName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is ActiveEvent &&
      other.eventKey == eventKey &&
      other.eventName == eventName &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(eventKey, eventName, updatedAt);
}

bool isEventNearby(
  String? startDate,
  String? endDate,
  DateTime today, {
  int days = 3,
}) {
  final start = _parseDate(startDate);
  if (start == null) return false;
  final end = _parseDate(endDate) ?? start;

  final latestStart = DateTime(today.year, today.month, today.day + days);
  final earliestEnd = DateTime(today.year, today.month, today.day - days);
  return !start.isAfter(latestStart) && !end.isBefore(earliestEnd);
}

DateTime? _parseDate(String? value) {
  final parsed = DateTime.tryParse(value ?? '');
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}
