import 'pit_model.dart';

enum PackingStatus {
  packing,
  staging,
  loading,
  ready;

  static final Map<String, PackingStatus> _byName = {
    for (final status in PackingStatus.values) status.name: status,
  };

  static PackingStatus fromString(String? value) =>
      tryParse(value) ?? PackingStatus.packing;

  static PackingStatus? tryParse(String? value) =>
      value == null ? null : _byName[value];
}

class PackingRecord implements PitModel {
  const PackingRecord({
    required this.id,
    required this.itemId,
    required this.packingStatus,
    this.photoRef,
    required this.updatedAt,
  });

  @override
  final String id;
  final String itemId;
  final PackingStatus packingStatus;
  final String? photoRef;
  final DateTime updatedAt;

  factory PackingRecord.fromJson(String id, Map<String, dynamic> data) {
    return PackingRecord(
      id: id,
      itemId: data['itemId'] as String? ?? '',
      packingStatus: PackingStatus.fromString(data['packingStatus'] as String?),
      photoRef: data['photoRef'] as String?,
      updatedAt:
          DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'packingStatus': packingStatus.name,
    if (photoRef != null) 'photoRef': photoRef,
    'updatedAt': updatedAt.toIso8601String(),
  };

  PackingRecord copyWith({
    String? itemId,
    PackingStatus? packingStatus,
    String? photoRef,
    DateTime? updatedAt,
  }) {
    return PackingRecord(
      id: id,
      itemId: itemId ?? this.itemId,
      packingStatus: packingStatus ?? this.packingStatus,
      photoRef: photoRef ?? this.photoRef,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
