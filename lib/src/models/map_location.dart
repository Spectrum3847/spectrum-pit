import 'pit_model.dart';

class MapLocation implements PitModel {
  const MapLocation({
    required this.id,
    required this.name,
    required this.mapType,
    required this.x,
    required this.y,
    this.inventoryItemId,
    required this.updatedAt,
  });

  @override
  final String id;
  final String name;
  final MapType mapType;
  final double x;
  final double y;
  final String? inventoryItemId;
  final DateTime updatedAt;

  factory MapLocation.fromJson(String id, Map<String, dynamic> data) {
    return MapLocation(
      id: id,
      name: data['name'] as String? ?? '',
      mapType: MapType.fromString(data['mapType'] as String?),
      x: (data['x'] as num?)?.toDouble() ?? 0,
      y: (data['y'] as num?)?.toDouble() ?? 0,
      inventoryItemId: data['inventoryItemId'] as String?,
      updatedAt:
          DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'mapType': mapType.name,
    'x': x,
    'y': y,
    if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  MapLocation copyWith({
    String? name,
    MapType? mapType,
    double? x,
    double? y,
    String? inventoryItemId,
    DateTime? updatedAt,
  }) {
    return MapLocation(
      id: id,
      name: name ?? this.name,
      mapType: mapType ?? this.mapType,
      x: x ?? this.x,
      y: y ?? this.y,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum MapType {
  lab,
  pit,
  vehicle;

  static final Map<String, MapType> _byName = {
    for (final type in MapType.values) type.name: type,
  };

  static MapType fromString(String? value) => tryParse(value) ?? MapType.lab;

  static MapType? tryParse(String? value) =>
      value == null ? null : _byName[value];
}
