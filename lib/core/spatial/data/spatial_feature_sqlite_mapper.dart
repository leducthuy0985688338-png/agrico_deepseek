import 'dart:convert';

import '../domain/entities/spatial_feature.dart';
import 'spatial_feature_json_codec.dart';
import 'spatial_geometry_json_codec.dart';
import 'spatial_sqlite_mapper_support.dart';

/// Maps [SpatialFeature] values to and from `spatial_features` rows.
abstract final class SpatialFeatureSqliteMapper {
  static Map<String, Object?> toRow(SpatialFeature feature) {
    feature.validate();
    return {
      'id': feature.id,
      'feature_type': feature.featureType,
      'geometry_type': feature.geometryType.name,
      'lifecycle_status': feature.lifecycleStatus.name,
      'project_id': feature.projectId,
      'business_unit_id': feature.businessUnitId,
      'code': feature.code,
      'name': feature.name,
      'created_at': feature.createdAt.toUtc().toIso8601String(),
      'created_by': feature.createdBy,
      'updated_at': feature.updatedAt.toUtc().toIso8601String(),
      'updated_by': feature.updatedBy,
      'schema_version': feature.schemaVersion,
      'geometry_json': feature.geometry == null
          ? null
          : jsonEncode(SpatialGeometryJsonCodec.encode(feature.geometry!)),
      'payload_json': jsonEncode(SpatialFeatureJsonCodec.encode(feature)),
    };
  }

  static SpatialFeature fromRow(Map<String, Object?> row) {
    final feature = SpatialFeatureJsonCodec.decode(
      SpatialSqliteMapperSupport.requiredJsonObject(row, 'payload_json'),
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'id'),
      feature.id,
      'id',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'feature_type'),
      feature.featureType,
      'feature_type',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'geometry_type'),
      feature.geometryType.name,
      'geometry_type',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'lifecycle_status'),
      feature.lifecycleStatus.name,
      'lifecycle_status',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'project_id'),
      feature.projectId,
      'project_id',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'business_unit_id'),
      feature.businessUnitId,
      'business_unit_id',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'code'),
      feature.code,
      'code',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'name'),
      feature.name,
      'name',
    );
    SpatialSqliteMapperSupport.expectDateTime(
      SpatialSqliteMapperSupport.requiredDateTime(row, 'created_at'),
      feature.createdAt,
      'created_at',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'created_by'),
      feature.createdBy,
      'created_by',
    );
    SpatialSqliteMapperSupport.expectDateTime(
      SpatialSqliteMapperSupport.requiredDateTime(row, 'updated_at'),
      feature.updatedAt,
      'updated_at',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'updated_by'),
      feature.updatedBy,
      'updated_by',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredInt(row, 'schema_version'),
      feature.schemaVersion,
      'schema_version',
    );
    _verifyGeometry(row, feature);
    return feature;
  }

  static void _verifyGeometry(
    Map<String, Object?> row,
    SpatialFeature feature,
  ) {
    final rowGeometry = SpatialSqliteMapperSupport.nullableJsonObject(
      row,
      'geometry_json',
    );
    final payloadGeometry = feature.geometry;
    if (rowGeometry == null || payloadGeometry == null) {
      if (rowGeometry != null || payloadGeometry != null) {
        throw const FormatException(
          'Spatial SQLite geometry_json contradicts canonical payload.',
        );
      }
      return;
    }
    final decoded = SpatialGeometryJsonCodec.decode(rowGeometry);
    SpatialSqliteMapperSupport.expectValue(
      jsonEncode(SpatialGeometryJsonCodec.encode(decoded)),
      jsonEncode(SpatialGeometryJsonCodec.encode(payloadGeometry)),
      'geometry_json',
    );
  }
}
