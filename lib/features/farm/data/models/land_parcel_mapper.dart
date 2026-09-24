import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';

abstract final class LandParcelMapper {
  static Map<String, Object?> toJson(
    LandParcel parcel, {
    bool includeHistory = true,
  }) => {
    'id': parcel.id,
    'farmId': parcel.farmId,
    'parcelCode': parcel.parcelCode,
    'name': parcel.name,
    'ownerHouseholdId': parcel.ownerHouseholdId,
    'ownerDisplayName': parcel.ownerDisplayName,
    'ownerContact': parcel.ownerContact,
    'active': parcel.active,
    'spatialFeatureId': parcel.spatialFeatureId,
    'countryCode': parcel.countryCode,
    'provinceCode': parcel.provinceCode,
    'districtCode': parcel.districtCode,
    'villageCode': parcel.villageCode,
    'createdAt': parcel.createdAt.toUtc().toIso8601String(),
    'createdBy': parcel.createdBy,
    'updatedAt': parcel.updatedAt.toUtc().toIso8601String(),
    'updatedBy': parcel.updatedBy,
    'schemaVersion': parcel.schemaVersion,
    'boundary': _polygonToJson(parcel.boundary),
    'centroid': _vertexToJson(parcel.centroid),
    'areaM2': parcel.areaM2,
    'areaHa': parcel.areaHa,
    'perimeterM': parcel.perimeterM,
    'boundarySource': parcel.boundarySource.name,
    'horizontalAccuracyM': parcel.horizontalAccuracyM,
    'measuredAt': parcel.measuredAt?.toUtc().toIso8601String(),
    'measuredBy': parcel.measuredBy,
    'verificationStatus': parcel.verificationStatus.name,
    'boundaryConfidence': parcel.boundaryConfidence,
    'boundaryVersion': parcel.boundaryVersion,
    'legacyMetadata': parcel.legacyMetadata,
    if (includeHistory)
      'boundaryHistory': parcel.boundaryHistory
          .map(boundaryVersionToJson)
          .toList(growable: false),
  };

  static LandParcel fromJson(
    Map<String, Object?> json, {
    Iterable<Map<String, Object?>>? history,
  }) {
    final historyMaps = history ?? _mapList(json['boundaryHistory']);
    return LandParcel.rehydrate(
      id: _string(json, 'id'),
      farmId: _string(json, 'farmId'),
      parcelCode: _string(json, 'parcelCode'),
      name: _string(json, 'name'),
      ownerHouseholdId: _optionalString(json['ownerHouseholdId']),
      ownerDisplayName: _optionalString(json['ownerDisplayName']),
      ownerContact: _optionalString(json['ownerContact']),
      active: _bool(json['active']),
      spatialFeatureId: _optionalString(json['spatialFeatureId']),
      countryCode: _optionalString(json['countryCode']),
      provinceCode: _optionalString(json['provinceCode']),
      districtCode: _optionalString(json['districtCode']),
      villageCode: _optionalString(json['villageCode']),
      createdAt: _date(json, 'createdAt'),
      createdBy: _string(json, 'createdBy'),
      updatedAt: _date(json, 'updatedAt'),
      updatedBy: _string(json, 'updatedBy'),
      schemaVersion: _integer(json, 'schemaVersion'),
      boundary: _polygon(json['boundary']),
      centroid: _vertex(json['centroid']),
      areaM2: _number(json, 'areaM2'),
      perimeterM: _number(json, 'perimeterM'),
      boundarySource: _enumValue(
        BoundarySource.values,
        _string(json, 'boundarySource'),
        'boundarySource',
      ),
      horizontalAccuracyM: _optionalNumber(json['horizontalAccuracyM']),
      measuredAt: _optionalDate(json['measuredAt']),
      measuredBy: _optionalString(json['measuredBy']),
      verificationStatus: _enumValue(
        BoundaryVerificationStatus.values,
        _string(json, 'verificationStatus'),
        'verificationStatus',
      ),
      boundaryConfidence: _optionalNumber(json['boundaryConfidence']),
      boundaryVersion: _integer(json, 'boundaryVersion'),
      boundaryHistory: historyMaps.map(boundaryVersionFromJson).toList(),
      legacyMetadata: _objectMap(json['legacyMetadata']),
    );
  }

  static Map<String, Object?> boundaryVersionToJson(
    LandParcelBoundaryVersion version,
  ) => {
    'id': version.id,
    'parcelId': version.parcelId,
    'version': version.version,
    'boundary': _polygonToJson(version.boundary),
    'centroid': _vertexToJson(version.centroid),
    'areaM2': version.areaM2,
    'areaHa': version.areaHa,
    'perimeterM': version.perimeterM,
    'source': version.source.name,
    'verificationStatus': version.verificationStatus.name,
    'horizontalAccuracyM': version.horizontalAccuracyM,
    'boundaryConfidence': version.boundaryConfidence,
    'occurredAt': version.occurredAt.toUtc().toIso8601String(),
    'actorMembershipId': version.actorMembershipId,
    'note': version.note,
    'sourceFileName': version.sourceFileName,
    'sourceFileHash': version.sourceFileHash,
  };

  static LandParcelBoundaryVersion boundaryVersionFromJson(
    Map<String, Object?> json,
  ) => LandParcelBoundaryVersion(
    id: _string(json, 'id'),
    parcelId: _string(json, 'parcelId'),
    version: _integer(json, 'version'),
    boundary: _polygon(json['boundary']),
    centroid: _vertex(json['centroid']),
    areaM2: _number(json, 'areaM2'),
    perimeterM: _number(json, 'perimeterM'),
    source: _enumValue(
      BoundarySource.values,
      _string(json, 'source'),
      'source',
    ),
    verificationStatus: _enumValue(
      BoundaryVerificationStatus.values,
      _string(json, 'verificationStatus'),
      'verificationStatus',
    ),
    horizontalAccuracyM: _optionalNumber(json['horizontalAccuracyM']),
    boundaryConfidence: _optionalNumber(json['boundaryConfidence']),
    occurredAt: _date(json, 'occurredAt'),
    actorMembershipId: _string(json, 'actorMembershipId'),
    note: _optionalString(json['note']),
    sourceFileName: _optionalString(json['sourceFileName']),
    sourceFileHash: _optionalString(json['sourceFileHash']),
  );

  static List<Map<String, Object?>> _polygonToJson(Wgs84Polygon polygon) =>
      polygon.vertices.map(_vertexToJson).toList(growable: false);

  static Map<String, Object?> _vertexToJson(Wgs84Vertex vertex) => {
    'latitude': vertex.latitude,
    'longitude': vertex.longitude,
    'altitudeM': vertex.altitudeM,
  };

  static Wgs84Polygon _polygon(Object? value) =>
      Wgs84Polygon.fromVertices(_mapList(value).map(_vertex));

  static Wgs84Vertex _vertex(Object? value) {
    final map = _objectMap(value);
    return Wgs84Vertex(
      latitude: _number(map, 'latitude'),
      longitude: _number(map, 'longitude'),
      altitudeM: _optionalNumber(map['altitudeM']),
    );
  }

  static List<Map<String, Object?>> _mapList(Object? value) {
    if (value is! Iterable) throw const FormatException('Expected a list.');
    return value.map(_objectMap).toList(growable: false);
  }

  static Map<String, Object?> _objectMap(Object? value) {
    if (value is! Map) throw const FormatException('Expected an object.');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = _optionalString(json[key]);
    if (value == null) throw FormatException('$key is required.');
    return value;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double _number(Map<String, Object?> json, String key) {
    final value = _optionalNumber(json[key]);
    if (value == null) throw FormatException('$key must be a finite number.');
    return value;
  }

  static double? _optionalNumber(Object? value) {
    if (value == null) return null;
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return number != null && number.isFinite ? number : null;
  }

  static int _integer(Map<String, Object?> json, String key) {
    final value = json[key];
    final number = value is num ? value.toInt() : int.tryParse('$value');
    if (number == null) throw FormatException('$key must be an integer.');
    return number;
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if ('$value'.toLowerCase() == 'true') return true;
    if ('$value'.toLowerCase() == 'false') return false;
    throw const FormatException('Expected a boolean.');
  }

  static DateTime _date(Map<String, Object?> json, String key) {
    final value = _optionalDate(json[key]);
    if (value == null) throw FormatException('$key must be a timestamp.');
    return value;
  }

  static DateTime? _optionalDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse('$value')?.toUtc();
  }

  static T _enumValue<T extends Enum>(
    Iterable<T> values,
    String name,
    String key,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('$key has an unsupported value.');
  }
}
