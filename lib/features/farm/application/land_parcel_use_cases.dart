import 'dart:typed_data';

import '../../../core/permissions/authorization.dart';
import '../data/interchange/kml_interchange.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/geometry/wgs84_geometry.dart';
import '../domain/entities/land_survey.dart';
import 'land_parcel_application_service.dart';

class CreateLandParcel {
  const CreateLandParcel(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcel>> call(
    AuthorizationSubject subject,
    CreateLandParcelCommand command,
  ) => application.createLandParcel(subject, command);
}

class UpdateLandParcelMetadata {
  const UpdateLandParcelMetadata(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcel>> call(
    AuthorizationSubject subject,
    UpdateLandParcelMetadataCommand command,
  ) => application.updateLandParcelMetadata(subject, command);
}

class ReplaceBoundary {
  const ReplaceBoundary(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcel>> call(
    AuthorizationSubject subject,
    ReplaceBoundaryCommand command,
  ) => application.replaceBoundary(subject, command);
}

class VerifyBoundary {
  const VerifyBoundary(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcel>> call(
    AuthorizationSubject subject,
    VerifyBoundaryCommand command,
  ) => application.verifyBoundary(subject, command);
}

class ImportKmlKmzPreview {
  const ImportKmlKmzPreview(this.application);
  final LandParcelApplication application;

  LandParcelApplicationResult<KmlImportDocument> kml(
    AuthorizationSubject subject, {
    required String farmId,
    required String source,
  }) => application.importKmlPreview(subject, farmId: farmId, kml: source);

  LandParcelApplicationResult<KmlImportDocument> kmz(
    AuthorizationSubject subject, {
    required String farmId,
    required Uint8List source,
  }) => application.importKmzPreview(subject, farmId: farmId, kmz: source);
}

class ApplyImportedBoundary {
  const ApplyImportedBoundary(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcel>> call(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
    required LandParcelImportPreview preview,
    required String actorMembershipId,
    required DateTime occurredAt,
    bool confirmVerifiedReplacement = false,
    String? sourceFileName,
    String? sourceFileHash,
  }) => application.applyImportedBoundary(
    subject,
    farmId: farmId,
    parcelId: parcelId,
    preview: preview,
    actorMembershipId: actorMembershipId,
    occurredAt: occurredAt,
    confirmVerifiedReplacement: confirmVerifiedReplacement,
    sourceFileName: sourceFileName,
    sourceFileHash: sourceFileHash,
  );
}

class ExportKmlKmz {
  const ExportKmlKmz(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcelExport>> call(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
    required LandParcelInterchangeFormat format,
  }) => application.exportKmlKmz(
    subject,
    farmId: farmId,
    parcelId: parcelId,
    format: format,
  );
}

class ReconcileLegacySpatialIdentity {
  const ReconcileLegacySpatialIdentity(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcel>> call(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
  }) => application.reconcileLegacySpatialIdentity(
    subject,
    farmId: farmId,
    parcelId: parcelId,
  );
}

/// Receives only a completed GPS ring. Live points remain ephemeral and cannot
/// create audit history until the existing measurement workflow confirms save.
class CompleteGpsMeasurement {
  const CompleteGpsMeasurement(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandParcel>> create(
    AuthorizationSubject subject, {
    required CreateLandParcelCommand command,
  }) {
    if (command.source != BoundarySource.gps) {
      return Future.value(
        const LandParcelApplicationResult.failure(
          LandParcelApplicationStatus.validationFailed,
          'landParcel.gps.invalidSource',
        ),
      );
    }
    return application.createLandParcel(subject, command);
  }

  Future<LandParcelApplicationResult<LandParcel>> replace(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
    required List<Wgs84Vertex> completedVertices,
    required String actorMembershipId,
    required DateTime occurredAt,
    double? horizontalAccuracyM,
    bool confirmVerifiedReplacement = false,
  }) => application.replaceBoundary(
    subject,
    ReplaceBoundaryCommand(
      farmId: farmId,
      parcelId: parcelId,
      vertices: completedVertices,
      source: BoundarySource.gps,
      actorMembershipId: actorMembershipId,
      occurredAt: occurredAt,
      horizontalAccuracyM: horizontalAccuracyM,
      confirmVerifiedReplacement: confirmVerifiedReplacement,
    ),
  );
}

/// Sprint 11: business metadata update for LandUseProfile.
///
/// Does NOT touch Spatial Core. Does NOT create SpatialFeatureRevision.
class UpdateLandUseProfile {
  const UpdateLandUseProfile(this.application);
  final LandParcelApplication application;

  Future<LandParcelApplicationResult<LandUseProfile>> call(
    AuthorizationSubject subject,
    UpdateLandUseProfileCommand command,
  ) => application.updateLandUseProfile(subject, command);
}
