import '../domain/entities/spatial_feature.dart';
import '../domain/geometry/spatial_geometry_type.dart';
import 'spatial_geometry_json_codec.dart';
import 'spatial_json_codec_support.dart';

/// Canonical JSON codec for [SpatialFeature] persistence payloads.
abstract final class SpatialFeatureJsonCodec {
  static Map<String, Object?> encode(SpatialFeature feature) {
    feature.validate();
    return {
      'id': feature.id,
      'featureType': feature.featureType,
      'geometryType': feature.geometryType.name,
      'geometry': feature.geometry == null
          ? null
          : SpatialGeometryJsonCodec.encode(feature.geometry!),
      'lifecycleStatus': feature.lifecycleStatus.name,
      'projectId': feature.projectId,
      'businessUnitId': feature.businessUnitId,
      'code': feature.code,
      'name': feature.name,
      'createdAt': feature.createdAt.toUtc().toIso8601String(),
      'createdBy': feature.createdBy,
      'updatedAt': feature.updatedAt.toUtc().toIso8601String(),
      'updatedBy': feature.updatedBy,
      'schemaVersion': feature.schemaVersion,
    };
  }

  static SpatialFeature decode(Map<String, Object?> json) {
    final geometryJson = SpatialJsonCodecSupport.nullableMap(json, 'geometry');
    final feature = SpatialFeature(
      id: SpatialJsonCodecSupport.requiredString(json, 'id'),
      featureType: SpatialJsonCodecSupport.requiredString(json, 'featureType'),
      geometryType: SpatialJsonCodecSupport.requiredEnum(
        json,
        'geometryType',
        SpatialGeometryType.values,
      ),
      geometry: geometryJson == null
          ? null
          : SpatialGeometryJsonCodec.decode(geometryJson),
      lifecycleStatus: SpatialJsonCodecSupport.requiredEnum(
        json,
        'lifecycleStatus',
        SpatialFeatureLifecycleStatus.values,
      ),
      projectId: SpatialJsonCodecSupport.nullableString(json, 'projectId'),
      businessUnitId: SpatialJsonCodecSupport.nullableString(
        json,
        'businessUnitId',
      ),
      code: SpatialJsonCodecSupport.nullableString(json, 'code'),
      name: SpatialJsonCodecSupport.nullableString(json, 'name'),
      createdAt: SpatialJsonCodecSupport.requiredDateTime(json, 'createdAt'),
      createdBy: SpatialJsonCodecSupport.requiredString(json, 'createdBy'),
      updatedAt: SpatialJsonCodecSupport.requiredDateTime(json, 'updatedAt'),
      updatedBy: SpatialJsonCodecSupport.requiredString(json, 'updatedBy'),
      schemaVersion: SpatialJsonCodecSupport.requiredInt(json, 'schemaVersion'),
    );
    feature.validate();
    return feature;
  }
}
