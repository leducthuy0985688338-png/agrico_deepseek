import 'dart:convert';

import '../domain/entities/spatial_feature_revision.dart';
import 'spatial_feature_revision_json_codec.dart';
import 'spatial_geometry_json_codec.dart';
import 'spatial_sqlite_mapper_support.dart';

/// Maps revisions to and from `spatial_feature_revisions` rows.
abstract final class SpatialFeatureRevisionSqliteMapper {
  static Map<String, Object?> toRow(SpatialFeatureRevision revision) {
    revision.validate();
    return {
      'id': revision.id,
      'feature_id': revision.featureId,
      'revision': revision.revision,
      'geometry_type': revision.geometryType.name,
      'geometry_json': revision.geometry == null
          ? null
          : jsonEncode(SpatialGeometryJsonCodec.encode(revision.geometry!)),
      'geometry_reference': revision.geometryReference,
      'temporal_state': revision.temporalState.name,
      'valid_from': revision.effectivePeriod.validFrom.toUtc().toIso8601String(),
      'valid_to': revision.effectivePeriod.validTo?.toUtc().toIso8601String(),
      'source_type': revision.source.type.name,
      'surveyed_at': revision.source.surveyedAt?.toUtc().toIso8601String(),
      'surveyed_by': revision.source.surveyedBy,
      'horizontal_accuracy_m': revision.source.horizontalAccuracyM,
      'source_reference': revision.source.sourceReference,
      'source_file_name': revision.source.sourceFileName,
      'source_file_hash': revision.source.sourceFileHash,
      'source_notes': revision.source.notes,
      'change_reason': revision.changeReason,
      'notes': revision.notes,
      'created_at': revision.createdAt.toUtc().toIso8601String(),
      'created_by': revision.createdBy,
      'schema_version': revision.schemaVersion,
      'payload_json': jsonEncode(
        SpatialFeatureRevisionJsonCodec.encode(revision),
      ),
    };
  }

  static SpatialFeatureRevision fromRow(Map<String, Object?> row) {
    final revision = SpatialFeatureRevisionJsonCodec.decode(
      SpatialSqliteMapperSupport.requiredJsonObject(row, 'payload_json'),
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'id'),
      revision.id,
      'id',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'feature_id'),
      revision.featureId,
      'feature_id',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredInt(row, 'revision'),
      revision.revision,
      'revision',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'geometry_type'),
      revision.geometryType.name,
      'geometry_type',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'geometry_reference'),
      revision.geometryReference,
      'geometry_reference',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'temporal_state'),
      revision.temporalState.name,
      'temporal_state',
    );
    SpatialSqliteMapperSupport.expectDateTime(
      SpatialSqliteMapperSupport.requiredDateTime(row, 'valid_from'),
      revision.effectivePeriod.validFrom,
      'valid_from',
    );
    SpatialSqliteMapperSupport.expectNullableDateTime(
      SpatialSqliteMapperSupport.nullableDateTime(row, 'valid_to'),
      revision.effectivePeriod.validTo,
      'valid_to',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'source_type'),
      revision.source.type.name,
      'source_type',
    );
    SpatialSqliteMapperSupport.expectNullableDateTime(
      SpatialSqliteMapperSupport.nullableDateTime(row, 'surveyed_at'),
      revision.source.surveyedAt,
      'surveyed_at',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'surveyed_by'),
      revision.source.surveyedBy,
      'surveyed_by',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableDouble(row, 'horizontal_accuracy_m'),
      revision.source.horizontalAccuracyM,
      'horizontal_accuracy_m',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'source_reference'),
      revision.source.sourceReference,
      'source_reference',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'source_file_name'),
      revision.source.sourceFileName,
      'source_file_name',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'source_file_hash'),
      revision.source.sourceFileHash,
      'source_file_hash',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'source_notes'),
      revision.source.notes,
      'source_notes',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'change_reason'),
      revision.changeReason,
      'change_reason',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.nullableString(row, 'notes'),
      revision.notes,
      'notes',
    );
    SpatialSqliteMapperSupport.expectDateTime(
      SpatialSqliteMapperSupport.requiredDateTime(row, 'created_at'),
      revision.createdAt,
      'created_at',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredString(row, 'created_by'),
      revision.createdBy,
      'created_by',
    );
    SpatialSqliteMapperSupport.expectValue(
      SpatialSqliteMapperSupport.requiredInt(row, 'schema_version'),
      revision.schemaVersion,
      'schema_version',
    );
    _verifyGeometry(row, revision);
    return revision;
  }

  static void _verifyGeometry(
    Map<String, Object?> row,
    SpatialFeatureRevision revision,
  ) {
    final rowGeometry = SpatialSqliteMapperSupport.nullableJsonObject(
      row,
      'geometry_json',
    );
    final payloadGeometry = revision.geometry;
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
