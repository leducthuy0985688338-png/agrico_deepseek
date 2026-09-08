import '../../../../models/field_model.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';

class LegacyFieldMigrationPolicy {
  const LegacyFieldMigrationPolicy({
    required this.farmId,
    required this.actorMembershipId,
    required this.occurredAt,
    required this.parcelCode,
    required this.isActive,
    required this.boundarySource,
    required this.verificationStatus,
  });

  final String farmId;
  final String actorMembershipId;
  final DateTime occurredAt;
  final String Function(FieldModel field) parcelCode;
  final bool Function(FieldModel field) isActive;
  final BoundarySource Function(FieldModel field) boundarySource;
  final BoundaryVerificationStatus Function(FieldModel field)
  verificationStatus;
}

abstract final class LegacyFieldAdapter {
  static LandParcel toLandParcel(
    FieldModel field,
    LegacyFieldMigrationPolicy policy,
  ) {
    final boundary = Wgs84Polygon.fromVertices(
      field.polygon.map(
        (point) =>
            Wgs84Vertex(latitude: point.latitude, longitude: point.longitude),
      ),
    );
    return LandParcel.create(
      id: field.id,
      farmId: policy.farmId,
      parcelCode: policy.parcelCode(field),
      name: field.name,
      boundary: boundary,
      boundarySource: policy.boundarySource(field),
      verificationStatus: policy.verificationStatus(field),
      actorMembershipId: policy.actorMembershipId,
      occurredAt: field.measuredAt ?? policy.occurredAt,
      active: policy.isActive(field),
      horizontalAccuracyM: field.gpsAccuracy,
      legacyMetadata: {
        'legacyType': 'FieldModel',
        'crop': field.crop,
        'status': field.status,
        'photoPaths': List<String>.of(field.photoPaths),
        'reportedArea': field.area,
        'reportedPerimeter': field.perimeter,
        'measurementMethod': field.measurementMethod,
        'measuredAt': field.measuredAt?.toUtc().toIso8601String(),
      },
    );
  }
}
