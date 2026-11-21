import 'pit_model.dart';

const int maxBorrowContactLength = 256;

class BorrowRecord implements PitModel {
  BorrowRecord({
    required this.id,
    this.itemId,
    required this.toolName,
    required this.teamName,
    required this.teamNumber,
    required this.competition,
    String? contact,
    required this.checkedOutAt,
    this.estimatedReturn,
    this.checkedInAt,
    required this.returned,
    required this.updatedAt,
  }) : contact = _clampContact(contact);

  static String? _clampContact(String? contact) {
    if (contact == null || contact.length <= maxBorrowContactLength) {
      return contact;
    }
    final clamped = StringBuffer();
    var used = 0;
    for (final rune in contact.runes) {
      final width = rune > 0xFFFF ? 2 : 1;
      if (used + width > maxBorrowContactLength) break;
      clamped.writeCharCode(rune);
      used += width;
    }
    return clamped.toString();
  }

  @override
  final String id;
  final String? itemId;
  final String toolName;
  final String teamName;
  final int teamNumber;
  final String competition;
  final String? contact;
  final DateTime checkedOutAt;
  final DateTime? estimatedReturn;
  final DateTime? checkedInAt;
  final bool returned;
  final DateTime updatedAt;

  bool isOverdueAt(DateTime now) =>
      !returned && estimatedReturn != null && now.isAfter(estimatedReturn!);

  factory BorrowRecord.fromJson(String id, Map<String, dynamic> data) {
    final estimatedReturnRaw = data['estimatedReturn'] as String?;
    final checkedInAtRaw = data['checkedInAt'] as String?;
    return BorrowRecord(
      id: id,
      itemId: data['itemId'] as String?,
      toolName: data['toolName'] as String? ?? '',
      teamName: data['teamName'] as String? ?? '',
      teamNumber: data['teamNumber'] as int? ?? 0,
      competition: data['competition'] as String? ?? '',
      contact: data['contact'] as String?,
      checkedOutAt:
          DateTime.tryParse(data['checkedOutAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      estimatedReturn: estimatedReturnRaw == null
          ? null
          : DateTime.tryParse(estimatedReturnRaw),
      checkedInAt: checkedInAtRaw == null
          ? null
          : DateTime.tryParse(checkedInAtRaw),
      returned: data['returned'] as bool? ?? false,
      updatedAt:
          DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    if (itemId != null) 'itemId': itemId,
    'toolName': toolName,
    'teamName': teamName,
    'teamNumber': teamNumber,
    'competition': competition,
    if (contact != null) 'contact': contact,
    'checkedOutAt': checkedOutAt.toIso8601String(),
    if (estimatedReturn != null)
      'estimatedReturn': estimatedReturn!.toIso8601String(),
    if (checkedInAt != null) 'checkedInAt': checkedInAt!.toIso8601String(),
    'returned': returned,
    'updatedAt': updatedAt.toIso8601String(),
  };

  BorrowRecord copyWith({
    String? itemId,
    String? toolName,
    String? teamName,
    int? teamNumber,
    String? competition,
    String? contact,
    DateTime? checkedOutAt,
    DateTime? estimatedReturn,
    DateTime? checkedInAt,
    bool? returned,
    DateTime? updatedAt,
  }) {
    return BorrowRecord(
      id: id,
      itemId: itemId ?? this.itemId,
      toolName: toolName ?? this.toolName,
      teamName: teamName ?? this.teamName,
      teamNumber: teamNumber ?? this.teamNumber,
      competition: competition ?? this.competition,
      contact: contact ?? this.contact,
      checkedOutAt: checkedOutAt ?? this.checkedOutAt,
      estimatedReturn: estimatedReturn ?? this.estimatedReturn,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      returned: returned ?? this.returned,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
