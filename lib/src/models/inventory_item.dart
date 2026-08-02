import 'pit_model.dart';

enum InventoryStatus {
  inLab,
  inPit,
  borrowed;

  static final Map<String, InventoryStatus> _byName = {
    for (final status in InventoryStatus.values) status.name: status,
  };

  static InventoryStatus fromString(String? value) =>
      tryParse(value) ?? InventoryStatus.inLab;

  static InventoryStatus? tryParse(String? value) =>
      value == null ? null : _byName[value];
}

class InventoryItem implements PitModel {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.labLocation,
    required this.pitLocation,
    this.mapRef,
    required this.status,
    required this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final String labLocation;
  final String pitLocation;
  final String? mapRef;
  final InventoryStatus status;
  final DateTime updatedAt;

  factory InventoryItem.fromJson(String id, Map<String, dynamic> data) {
    return InventoryItem(
      id: id,
      name: data['name'] as String? ?? '',
      labLocation: data['labLocation'] as String? ?? '',
      pitLocation: data['pitLocation'] as String? ?? '',
      mapRef: data['mapRef'] as String?,
      status: InventoryStatus.fromString(data['status'] as String?),
      updatedAt:
          DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'labLocation': labLocation,
    'pitLocation': pitLocation,
    if (mapRef != null) 'mapRef': mapRef,
    'status': status.name,
    'updatedAt': updatedAt.toIso8601String(),
  };

  InventoryItem copyWith({
    String? name,
    String? labLocation,
    String? pitLocation,
    String? mapRef,
    InventoryStatus? status,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id,
      name: name ?? this.name,
      labLocation: labLocation ?? this.labLocation,
      pitLocation: pitLocation ?? this.pitLocation,
      mapRef: mapRef ?? this.mapRef,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
