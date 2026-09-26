import 'dart:convert';

import 'package:agrico_deepseek/core/spatial/data/spatial_feature_revision_json_codec.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature_revision.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_source.dart';
import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_temporal.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_coordinate.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_geometry_type.dart';
import 'package:agrico_deepseek/core/spatial/domain/geometry/spatial_linear_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SpatialFeatureRevision buildRevision({
    SpatialTemporalState temporalState = SpatialTemporalState.asBuilt,
    DateTime? validTo,
    SpatialSourceType sourceType = SpatialSourceType.survey,
    String? geometryReference = 'geometry/blob/2',
    int revision = 2,
    int schemaVersion = 4,
  }) => SpatialFeatureRevision(
    id: 'revision-2',
    featureId: 'feature-1',
    revision: revision,
    geometryType: SpatialGeometryType.point,
    geometry: const SpatialPoint(
      coordinate: SpatialCoordinate(
        latitude: 16.5,
        longitude: 104.7,
        altitudeM: null,
      ),
    ),
    temporalState: temporalState,
    effectivePeriod: SpatialEffectivePeriod(
      validFrom: DateTime.parse('2026-02-03T04:05:06+07:00'),
      validTo: validTo,
    ),
    source: SpatialSource(
      type: sourceType,
      surveyedAt: DateTime.parse('2026-02-02T03:04:05+07:00'),
      surveyedBy: 'surveyor-1',
      horizontalAccuracyM: 0.0123456789,
      sourceReference: 'job-ລາວ-01',
      sourceFileName: 'ranh-giới.dwg',
      sourceFileHash: 'sha256:abc',
      notes: 'Nguồn Việt / ລາວ / English',
    ),
    geometryReference: geometryReference,
    changeReason: 'Điều chỉnh mốc ທີ່ດິນ',
    notes: 'Revision notes Việt–Lào',
    createdAt: DateTime.parse('2026-02-03T05:06:07+07:00'),
    createdBy: 'user-2',
    schemaVersion: schemaVersion,
  );

  Map<String, Object?> completeJson() => {
    'id': 'revision-2',
    'identity': {'featureId': 'feature-1', 'revision': 2},
    'geometryType': 'point',
    'geometry': {
      'type': 'point',
      'coordinate': {'latitude': 16.5, 'longitude': 104.7, 'altitudeM': null},
    },
    'geometryReference': 'geometry/blob/2',
    'temporalState': 'asBuilt',
    'effectivePeriod': {
      'validFrom': '2026-02-02T21:05:06.000Z',
      'validTo': null,
    },
    'source': {
      'type': 'survey',
      'surveyedAt': '2026-02-01T20:04:05.000Z',
      'surveyedBy': 'surveyor-1',
      'horizontalAccuracyM': 0.0123456789,
      'sourceReference': 'job-ລາວ-01',
      'sourceFileName': 'ranh-giới.dwg',
      'sourceFileHash': 'sha256:abc',
      'notes': 'Nguồn Việt / ລາວ / English',
    },
    'changeReason': 'Điều chỉnh mốc ທີ່ດິນ',
    'notes': 'Revision notes Việt–Lào',
    'createdAt': '2026-02-02T22:06:07.000Z',
    'createdBy': 'user-2',
    'schemaVersion': 4,
  };

  void expectRevision(
    SpatialFeatureRevision actual,
    SpatialFeatureRevision expected,
  ) {
    expect(actual.id, expected.id);
    expect(actual.featureId, expected.featureId);
    expect(actual.revision, expected.revision);
    expect(actual.geometryType, expected.geometryType);
    expect(actual.temporalState, expected.temporalState);
    expect(
      actual.effectivePeriod.validFrom,
      expected.effectivePeriod.validFrom.toUtc(),
    );
    expect(
      actual.effectivePeriod.validTo,
      expected.effectivePeriod.validTo?.toUtc(),
    );
    expect(actual.geometryReference, expected.geometryReference);
    expect(actual.changeReason, expected.changeReason);
    expect(actual.notes, expected.notes);
    expect(actual.createdAt, expected.createdAt.toUtc());
    expect(actual.createdBy, expected.createdBy);
    expect(actual.schemaVersion, expected.schemaVersion);
    expect(
      (actual.geometry as SpatialPoint).coordinate,
      (expected.geometry as SpatialPoint).coordinate,
    );
    expect(actual.source.type, expected.source.type);
    expect(actual.source.surveyedAt, expected.source.surveyedAt?.toUtc());
    expect(actual.source.surveyedBy, expected.source.surveyedBy);
    expect(
      actual.source.horizontalAccuracyM,
      expected.source.horizontalAccuracyM,
    );
    expect(actual.source.sourceReference, expected.source.sourceReference);
    expect(actual.source.sourceFileName, expected.source.sourceFileName);
    expect(actual.source.sourceFileHash, expected.source.sourceFileHash);
    expect(actual.source.notes, expected.source.notes);
  }

  test('encodes a complete revision using the exact canonical structure', () {
    expect(
      SpatialFeatureRevisionJsonCodec.encode(buildRevision()),
      completeJson(),
    );
  });

  test('round-trips concrete geometry, identity, metadata and provenance', () {
    expectRevision(
      SpatialFeatureRevisionJsonCodec.decode(completeJson()),
      buildRevision(),
    );
  });

  test('preserves legacy geometryReference', () {
    expect(
      SpatialFeatureRevisionJsonCodec.decode(completeJson()).geometryReference,
      'geometry/blob/2',
    );
  });

  test('preserves every temporal state', () {
    for (final state in SpatialTemporalState.values) {
      final source = buildRevision(temporalState: state);
      expect(
        SpatialFeatureRevisionJsonCodec.decode(
          SpatialFeatureRevisionJsonCodec.encode(source),
        ).temporalState,
        state,
      );
    }
  });

  test('preserves bounded effective period', () {
    final validTo = DateTime.parse('2026-03-03T04:05:06+07:00');
    final source = buildRevision(validTo: validTo);
    final decoded = SpatialFeatureRevisionJsonCodec.decode(
      SpatialFeatureRevisionJsonCodec.encode(source),
    );
    expect(decoded.effectivePeriod.validTo, validTo.toUtc());
  });

  test('preserves null validTo and all optional source fields as null', () {
    final json = completeJson();
    final source = Map<String, Object?>.from(json['source']! as Map)
      ..updateAll((key, value) => key == 'type' ? value : null);
    json['source'] = source;
    json['geometryReference'] = null;
    json['changeReason'] = null;
    json['notes'] = null;
    final decoded = SpatialFeatureRevisionJsonCodec.decode(json);
    expect(decoded.effectivePeriod.validTo, isNull);
    expect(decoded.source.surveyedAt, isNull);
    expect(decoded.source.surveyedBy, isNull);
    expect(decoded.source.horizontalAccuracyM, isNull);
    expect(decoded.source.sourceReference, isNull);
    expect(decoded.source.sourceFileName, isNull);
    expect(decoded.source.sourceFileHash, isNull);
    expect(decoded.source.notes, isNull);
  });

  test('preserves every source type', () {
    for (final type in SpatialSourceType.values) {
      final source = buildRevision(sourceType: type);
      expect(
        SpatialFeatureRevisionJsonCodec.decode(
          SpatialFeatureRevisionJsonCodec.encode(source),
        ).source.type,
        type,
      );
    }
  });

  test('preserves Unicode metadata, timestamps and schemaVersion', () {
    final decoded = SpatialFeatureRevisionJsonCodec.decode(completeJson());
    expect(decoded.changeReason, 'Điều chỉnh mốc ທີ່ດິນ');
    expect(decoded.notes, 'Revision notes Việt–Lào');
    expect(decoded.source.sourceReference, 'job-ລາວ-01');
    expect(decoded.createdAt.isUtc, isTrue);
    expect(decoded.schemaVersion, 4);
  });

  test('jsonEncode/jsonDecode round-trip is semantically lossless', () {
    final source = buildRevision();
    final json =
        jsonDecode(jsonEncode(SpatialFeatureRevisionJsonCodec.encode(source)))
            as Map<String, dynamic>;
    expectRevision(SpatialFeatureRevisionJsonCodec.decode(json), source);
  });

  test('rejects unknown temporal state', () {
    final json = completeJson()..['temporalState'] = 'future';
    expect(
      () => SpatialFeatureRevisionJsonCodec.decode(json),
      throwsFormatException,
    );
  });

  test('rejects unknown source type', () {
    final json = completeJson();
    json['source'] = Map<String, Object?>.from(json['source']! as Map)
      ..['type'] = 'unknown';
    expect(
      () => SpatialFeatureRevisionJsonCodec.decode(json),
      throwsFormatException,
    );
  });

  test('rejects missing identity members', () {
    for (final field in ['featureId', 'revision']) {
      final json = completeJson();
      json['identity'] = Map<String, Object?>.from(json['identity']! as Map)
        ..remove(field);
      expect(
        () => SpatialFeatureRevisionJsonCodec.decode(json),
        throwsFormatException,
      );
    }
  });

  test('rejects revision <= 0', () {
    for (final value in [0, -1]) {
      final json = completeJson();
      json['identity'] = Map<String, Object?>.from(json['identity']! as Map)
        ..['revision'] = value;
      expect(
        () => SpatialFeatureRevisionJsonCodec.decode(json),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid effective period', () {
    final json = completeJson();
    json['effectivePeriod'] = {
      'validFrom': '2026-03-01T00:00:00.000Z',
      'validTo': '2026-02-01T00:00:00.000Z',
    };
    expect(
      () => SpatialFeatureRevisionJsonCodec.decode(json),
      throwsFormatException,
    );
  });

  test('rejects invalid DateTime', () {
    final json = completeJson()..['createdAt'] = 'not-a-date';
    expect(
      () => SpatialFeatureRevisionJsonCodec.decode(json),
      throwsFormatException,
    );
  });

  test('rejects malformed concrete geometry', () {
    final json = completeJson()..['geometry'] = {'type': 'point'};
    expect(
      () => SpatialFeatureRevisionJsonCodec.decode(json),
      throwsFormatException,
    );
  });

  test('rejects geometryType and payload mismatch', () {
    final json = completeJson()..['geometryType'] = 'polygon';
    expect(
      () => SpatialFeatureRevisionJsonCodec.decode(json),
      throwsFormatException,
    );
  });

  test('rejects wrong nested JSON structures', () {
    for (final field in ['identity', 'effectivePeriod', 'source']) {
      final json = completeJson()..[field] = <Object?>[];
      expect(
        () => SpatialFeatureRevisionJsonCodec.decode(json),
        throwsFormatException,
      );
    }
  });

  test('rejects missing required source data', () {
    final json = completeJson();
    json['source'] = Map<String, Object?>.from(json['source']! as Map)
      ..remove('type');
    expect(
      () => SpatialFeatureRevisionJsonCodec.decode(json),
      throwsFormatException,
    );
  });

  test('rejects missing, wrong or non-positive schemaVersion', () {
    for (final value in <Object?>[null, '4', 0, -1, 4.0]) {
      final json = completeJson();
      if (value == null) {
        json.remove('schemaVersion');
      } else {
        json['schemaVersion'] = value;
      }
      expect(
        () => SpatialFeatureRevisionJsonCodec.decode(json),
        throwsFormatException,
      );
    }
  });
}
