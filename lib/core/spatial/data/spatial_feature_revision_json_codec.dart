import '../domain/entities/spatial_feature_revision.dart';
import '../domain/entities/spatial_source.dart';
import '../domain/entities/spatial_temporal.dart';
import '../domain/geometry/spatial_geometry_type.dart';
import 'spatial_geometry_json_codec.dart';
import 'spatial_json_codec_support.dart';

/// Canonical JSON codec for [SpatialFeatureRevision] persistence payloads.
abstract final class SpatialFeatureRevisionJsonCodec {
  static Map<String, Object?> encode(SpatialFeatureRevision revision) {
    revision.validate();
    return {
      'id': revision.id,
      'identity': {
        'featureId': revision.featureId,
        'revision': revision.revision,
      },
      'geometryType': revision.geometryType.name,
      'geometry': revision.geometry == null
          ? null
          : SpatialGeometryJsonCodec.encode(revision.geometry!),
      'geometryReference': revision.geometryReference,
      'temporalState': revision.temporalState.name,
      'effectivePeriod': {
        'validFrom': revision.effectivePeriod.validFrom
            .toUtc()
            .toIso8601String(),
        'validTo': revision.effectivePeriod.validTo?.toUtc().toIso8601String(),
      },
      'source': {
        'type': revision.source.type.name,
        'surveyedAt': revision.source.surveyedAt?.toUtc().toIso8601String(),
        'surveyedBy': revision.source.surveyedBy,
        'horizontalAccuracyM': revision.source.horizontalAccuracyM,
        'sourceReference': revision.source.sourceReference,
        'sourceFileName': revision.source.sourceFileName,
        'sourceFileHash': revision.source.sourceFileHash,
        'notes': revision.source.notes,
      },
      'changeReason': revision.changeReason,
      'notes': revision.notes,
      'createdAt': revision.createdAt.toUtc().toIso8601String(),
      'createdBy': revision.createdBy,
      'schemaVersion': revision.schemaVersion,
    };
  }

  static SpatialFeatureRevision decode(Map<String, Object?> json) {
    final identity = SpatialJsonCodecSupport.requiredMap(json, 'identity');
    final geometryJson = SpatialJsonCodecSupport.nullableMap(json, 'geometry');
    final period = SpatialJsonCodecSupport.requiredMap(json, 'effectivePeriod');
    final sourceJson = SpatialJsonCodecSupport.requiredMap(json, 'source');

    final revision = SpatialFeatureRevision(
      id: SpatialJsonCodecSupport.requiredString(json, 'id'),
      featureId: SpatialJsonCodecSupport.requiredString(identity, 'featureId'),
      revision: SpatialJsonCodecSupport.requiredInt(identity, 'revision'),
      geometryType: SpatialJsonCodecSupport.requiredEnum(
        json,
        'geometryType',
        SpatialGeometryType.values,
      ),
      geometry: geometryJson == null
          ? null
          : SpatialGeometryJsonCodec.decode(geometryJson),
      geometryReference: SpatialJsonCodecSupport.nullableString(
        json,
        'geometryReference',
      ),
      temporalState: SpatialJsonCodecSupport.requiredEnum(
        json,
        'temporalState',
        SpatialTemporalState.values,
      ),
      effectivePeriod: SpatialEffectivePeriod(
        validFrom: SpatialJsonCodecSupport.requiredDateTime(
          period,
          'validFrom',
        ),
        validTo: SpatialJsonCodecSupport.nullableDateTime(period, 'validTo'),
      ),
      source: SpatialSource(
        type: SpatialJsonCodecSupport.requiredEnum(
          sourceJson,
          'type',
          SpatialSourceType.values,
        ),
        surveyedAt: SpatialJsonCodecSupport.nullableDateTime(
          sourceJson,
          'surveyedAt',
        ),
        surveyedBy: SpatialJsonCodecSupport.nullableString(
          sourceJson,
          'surveyedBy',
        ),
        horizontalAccuracyM: SpatialJsonCodecSupport.nullableDouble(
          sourceJson,
          'horizontalAccuracyM',
        ),
        sourceReference: SpatialJsonCodecSupport.nullableString(
          sourceJson,
          'sourceReference',
        ),
        sourceFileName: SpatialJsonCodecSupport.nullableString(
          sourceJson,
          'sourceFileName',
        ),
        sourceFileHash: SpatialJsonCodecSupport.nullableString(
          sourceJson,
          'sourceFileHash',
        ),
        notes: SpatialJsonCodecSupport.nullableString(sourceJson, 'notes'),
      ),
      changeReason: SpatialJsonCodecSupport.nullableString(
        json,
        'changeReason',
      ),
      notes: SpatialJsonCodecSupport.nullableString(json, 'notes'),
      createdAt: SpatialJsonCodecSupport.requiredDateTime(json, 'createdAt'),
      createdBy: SpatialJsonCodecSupport.requiredString(json, 'createdBy'),
      schemaVersion: SpatialJsonCodecSupport.requiredInt(json, 'schemaVersion'),
    );
    revision.validate();
    return revision;
  }
}
