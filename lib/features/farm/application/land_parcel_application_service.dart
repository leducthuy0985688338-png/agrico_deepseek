import 'dart:typed_data';

import '../../../core/permissions/authorization.dart';
import '../data/interchange/kml_interchange.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/entities/land_survey.dart';
import '../domain/repositories/land_survey_repository.dart';
import '../domain/geometry/wgs84_geometry.dart';
import '../domain/repositories/land_parcel_repository.dart';
import '../../../core/spatial/domain/entities/spatial_temporal.dart';
import 'land_parcel_spatial_sync_workflow.dart';
import 'land_parcel_boundary_consistency_queries.dart';

enum LandParcelApplicationStatus {
  success,
  permissionDenied,
  confirmationRequired,
  validationFailed,
  notFound,
  persistenceFailed,
  interchangeFailed,
}

class LandParcelApplicationResult<T> {
  const LandParcelApplicationResult._({
    required this.status,
    required this.messageKey,
    this.value,
    this.error,
  });

  const LandParcelApplicationResult.success(T value, String messageKey)
    : this._(
        status: LandParcelApplicationStatus.success,
        messageKey: messageKey,
        value: value,
      );

  const LandParcelApplicationResult.failure(
    LandParcelApplicationStatus status,
    String messageKey, {
    Object? error,
  }) : this._(status: status, messageKey: messageKey, error: error);

  final LandParcelApplicationStatus status;
  final String messageKey;
  final T? value;
  final Object? error;

  bool get isSuccess => status == LandParcelApplicationStatus.success;

  /// Forces an atomic persistence boundary to roll back when persistence
  /// has already been converted into an application result.
  void requireSuccessForAtomicPersistence() {
    if (status == LandParcelApplicationStatus.persistenceFailed) {
      throw LandParcelAtomicPersistenceException(this);
    }
  }
}

/// Internal signal used to make an outer atomic transaction roll back while
/// preserving the application result that should be returned to the caller.
class LandParcelAtomicPersistenceException implements Exception {
  const LandParcelAtomicPersistenceException(this.result);

  final LandParcelApplicationResult<Object?> result;

  @override
  String toString() =>
      'LandParcelAtomicPersistenceException: ${result.messageKey}';
}

class CreateLandParcelCommand {
  const CreateLandParcelCommand({
    required this.id,
    required this.farmId,
    required this.parcelCode,
    required this.name,
    required this.vertices,
    required this.source,
    required this.actorMembershipId,
    required this.occurredAt,
    this.ownerHouseholdId,
    this.ownerDisplayName,
    this.ownerContact,
    this.horizontalAccuracyM,
    this.boundaryConfidence,
    this.legacyMetadata = const {},
  });

  final String id;
  final String farmId;
  final String parcelCode;
  final String name;
  final List<Wgs84Vertex> vertices;
  final BoundarySource source;
  final String actorMembershipId;
  final DateTime occurredAt;
  final String? ownerHouseholdId;
  final String? ownerDisplayName;
  final String? ownerContact;
  final double? horizontalAccuracyM;
  final double? boundaryConfidence;
  final Map<String, Object?> legacyMetadata;
}

class UpdateLandParcelMetadataCommand {
  const UpdateLandParcelMetadataCommand({
    required this.farmId,
    required this.parcelId,
    required this.actorMembershipId,
    required this.occurredAt,
    this.parcelCode,
    this.name,
    this.ownerHouseholdId,
    this.ownerDisplayName,
    this.ownerContact,
    this.active,
    this.countryCode,
    this.provinceCode,
    this.districtCode,
    this.villageCode,
  });

  final String farmId;
  final String parcelId;
  final String actorMembershipId;
  final DateTime occurredAt;
  final String? parcelCode;
  final String? name;
  final String? ownerHouseholdId;
  final String? ownerDisplayName;
  final String? ownerContact;
  final bool? active;
  final String? countryCode;
  final String? provinceCode;
  final String? districtCode;
  final String? villageCode;
}

class ReplaceBoundaryCommand {
  const ReplaceBoundaryCommand({
    required this.farmId,
    required this.parcelId,
    required this.vertices,
    required this.source,
    required this.actorMembershipId,
    required this.occurredAt,
    this.horizontalAccuracyM,
    this.boundaryConfidence,
    this.confirmVerifiedReplacement = false,
    this.note,
    this.sourceFileName,
    this.sourceFileHash,
  });

  final String farmId;
  final String parcelId;
  final List<Wgs84Vertex> vertices;
  final BoundarySource source;
  final String actorMembershipId;
  final DateTime occurredAt;
  final double? horizontalAccuracyM;
  final double? boundaryConfidence;
  final bool confirmVerifiedReplacement;
  final String? note;
  final String? sourceFileName;
  final String? sourceFileHash;
}

class UpdateLandUseProfileCommand {
  const UpdateLandUseProfileCommand({
    required this.farmId,
    required this.parcelId,
    required this.actorMembershipId,
    required this.occurredAt,
    this.landUseType,
    this.currentCondition,
    this.clearingStatus,
    this.readinessStatus,
    this.notes,
  });

  final String farmId;
  final String parcelId;
  final String actorMembershipId;
  final DateTime occurredAt;
  final LandUseType? landUseType;
  final LandCondition? currentCondition;
  final ClearingStatus? clearingStatus;
  final ReadinessStatus? readinessStatus;
  final String? notes;
}

class VerifyBoundaryCommand {
  const VerifyBoundaryCommand({
    required this.farmId,
    required this.parcelId,
    required this.status,
    required this.actorMembershipId,
    required this.occurredAt,
  });

  final String farmId;
  final String parcelId;
  final BoundaryVerificationStatus status;
  final String actorMembershipId;
  final DateTime occurredAt;
}

enum LandParcelInterchangeFormat { kml, kmz }

class LandParcelExport {
  const LandParcelExport({
    required this.format,
    required this.fileName,
    this.text,
    this.bytes,
  });

  final LandParcelInterchangeFormat format;
  final String fileName;
  final String? text;
  final Uint8List? bytes;
}

abstract interface class LandParcelApplication {
  Future<LandParcelApplicationResult<LandParcel>> createLandParcel(
    AuthorizationSubject subject,
    CreateLandParcelCommand command,
  );

  Future<LandParcelApplicationResult<LandParcel>> updateLandParcelMetadata(
    AuthorizationSubject subject,
    UpdateLandParcelMetadataCommand command,
  );

  Future<LandParcelApplicationResult<LandParcel>> replaceBoundary(
    AuthorizationSubject subject,
    ReplaceBoundaryCommand command,
  );

  Future<LandParcelApplicationResult<LandParcel>> verifyBoundary(
    AuthorizationSubject subject,
    VerifyBoundaryCommand command,
  );

  LandParcelApplicationResult<KmlImportDocument> importKmlPreview(
    AuthorizationSubject subject, {
    required String farmId,
    required String kml,
  });

  LandParcelApplicationResult<KmlImportDocument> importKmzPreview(
    AuthorizationSubject subject, {
    required String farmId,
    required Uint8List kmz,
  });

  Future<LandParcelApplicationResult<LandParcel>> applyImportedBoundary(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
    required LandParcelImportPreview preview,
    required String actorMembershipId,
    required DateTime occurredAt,
    bool confirmVerifiedReplacement = false,
    String? sourceFileName,
    String? sourceFileHash,
  });

  Future<LandParcelApplicationResult<LandParcelExport>> exportKmlKmz(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
    required LandParcelInterchangeFormat format,
  });

  /// Explicit, permission-gated repair for an otherwise consistent legacy row.
  Future<LandParcelApplicationResult<LandParcel>> reconcileLegacySpatialIdentity(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
  });

  /// Sprint 11: business metadata update.
  ///
  /// Updates LandUseProfile ONLY. Does NOT touch Spatial Core:
  /// - no SpatialFeatureRevision
  /// - no boundaryVersion increment
  /// - no SpatialFeature identity change.
  Future<LandParcelApplicationResult<LandUseProfile>> updateLandUseProfile(
    AuthorizationSubject subject,
    UpdateLandUseProfileCommand command,
  );
}

class LandParcelApplicationService implements LandParcelApplication {
  const LandParcelApplicationService({
    required this.repository,
    this.authorization = const AuthorizationService(),
    this.interchange = const KmlInterchangeCodec(),
    this.spatialWorkflow,
    this.landSurveyRepository,
    this.boundaryConsistencyQueries,
  });

  final LandParcelRepository repository;
  final AuthorizationService authorization;
  final KmlInterchangeCodec interchange;
  final LandParcelBoundaryConsistencyQueries? boundaryConsistencyQueries;

  /// Optional land survey repository for business metadata writes.
  ///
  /// Sprint 11: required for [updateLandUseProfile]. If null, that
  /// operation returns a persistence failure.
  final LandSurveyRepository? landSurveyRepository;

  /// Optional production spatial synchronization workflow.
  ///
  /// Production composition MUST inject a non-null workflow.
  /// Null exists only for backward compatibility with legacy
  /// tests/callers that pre-date spatial integration.
  final LandParcelSpatialSyncWorkflow? spatialWorkflow;

  /// Reuses the same application policy with a transaction-scoped repository.
  ///
  /// This does not open or own a transaction. The supplied repository decides
  /// whether persistence joins an existing transaction or creates its own.
  LandParcelApplicationService withRepository(
    LandParcelRepository scopedRepository,
  ) => LandParcelApplicationService(
    repository: scopedRepository,
    authorization: authorization,
    interchange: interchange,
    spatialWorkflow: spatialWorkflow,
    landSurveyRepository: landSurveyRepository,
    boundaryConsistencyQueries: boundaryConsistencyQueries,
  );

  @override
  Future<LandParcelApplicationResult<LandParcel>> createLandParcel(
    AuthorizationSubject subject,
    CreateLandParcelCommand command,
  ) async {
    final resource = ResourceContext(
      farmId: command.farmId,
      fieldId: command.id,
      ownerUserId: subject.userId,
    );
    final permissions = <String>[
      PermissionCodes.fieldCreate,
      if (command.source == BoundarySource.gps) PermissionCodes.fieldMeasure,
      if (command.source == BoundarySource.googleEarth ||
          command.source == BoundarySource.imported)
        PermissionCodes.fieldGoogleEarthImport,
    ];
    if (!_canAll(subject, resource, permissions)) {
      return _denied();
    }
    try {
      final workflow = spatialWorkflow;
      if (workflow != null) {
        final spatialFeatureId = workflow.identityGenerator.newId(
          'spatial-feature',
        );

        final parcel = LandParcel.create(
          id: command.id,
          farmId: command.farmId,
          parcelCode: command.parcelCode,
          name: command.name,
          ownerHouseholdId: command.ownerHouseholdId,
          ownerDisplayName: command.ownerDisplayName,
          ownerContact: command.ownerContact,
          boundary: Wgs84Polygon.fromVertices(command.vertices),
          boundarySource: command.source,
          verificationStatus: BoundaryVerificationStatus.measured,
          actorMembershipId: command.actorMembershipId,
          occurredAt: command.occurredAt,
          horizontalAccuracyM: command.horizontalAccuracyM,
          boundaryConfidence: command.boundaryConfidence,
          legacyMetadata: command.legacyMetadata,
          spatialFeatureId: spatialFeatureId,
        );

        await workflow.create(
          parcel: parcel,
          temporalState: SpatialTemporalState.baseline,
        );

        return LandParcelApplicationResult.success(
          parcel,
          'landParcel.create.success',
        );
      }

      final parcel = LandParcel.create(
        id: command.id,
        farmId: command.farmId,
        parcelCode: command.parcelCode,
        name: command.name,
        ownerHouseholdId: command.ownerHouseholdId,
        ownerDisplayName: command.ownerDisplayName,
        ownerContact: command.ownerContact,
        boundary: Wgs84Polygon.fromVertices(command.vertices),
        boundarySource: command.source,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: command.actorMembershipId,
        occurredAt: command.occurredAt,
        horizontalAccuracyM: command.horizontalAccuracyM,
        boundaryConfidence: command.boundaryConfidence,
        legacyMetadata: command.legacyMetadata,
      );
      await repository.transaction((transaction) => transaction.create(parcel));
      return LandParcelApplicationResult.success(
        parcel,
        'landParcel.create.success',
      );
    } on FormatException catch (error) {
      return _validation(error);
    } catch (error) {
      return _persistence(error);
    }
  }

  @override
  Future<LandParcelApplicationResult<LandParcel>> updateLandParcelMetadata(
    AuthorizationSubject subject,
    UpdateLandParcelMetadataCommand command,
  ) => _mutateExisting(
    subject: subject,
    farmId: command.farmId,
    parcelId: command.parcelId,
    permissions: const [PermissionCodes.fieldEdit],
    mutation: (parcel) => parcel.updateMetadata(
      parcelCode: command.parcelCode,
      name: command.name,
      ownerHouseholdId: command.ownerHouseholdId,
      ownerDisplayName: command.ownerDisplayName,
      ownerContact: command.ownerContact,
      active: command.active,
      countryCode: command.countryCode,
      provinceCode: command.provinceCode,
      districtCode: command.districtCode,
      villageCode: command.villageCode,
      actorMembershipId: command.actorMembershipId,
      occurredAt: command.occurredAt,
    ),
    successKey: 'landParcel.update.success',
  );

  @override
  Future<LandParcelApplicationResult<LandParcel>> replaceBoundary(
    AuthorizationSubject subject,
    ReplaceBoundaryCommand command,
  ) async {
    final permissions = <String>[
      PermissionCodes.fieldBoundaryEdit,
      if (command.source == BoundarySource.gps) PermissionCodes.fieldMeasure,
      if (command.source == BoundarySource.googleEarth ||
          command.source == BoundarySource.imported)
        PermissionCodes.fieldGoogleEarthImport,
    ];
    final resource = ResourceContext(
      farmId: command.farmId,
      fieldId: command.parcelId,
    );
    if (!_canAll(subject, resource, permissions)) return _denied();
    final parcel = await repository.getById(
      farmId: command.farmId,
      id: command.parcelId,
    );
    if (parcel == null) return _notFound();
    if (parcel.verificationStatus == BoundaryVerificationStatus.verified) {
      if (!command.confirmVerifiedReplacement) {
        return const LandParcelApplicationResult.failure(
          LandParcelApplicationStatus.confirmationRequired,
          'landParcel.boundary.verifiedConfirmation',
        );
      }
      if (!_can(subject, resource, PermissionCodes.fieldBoundaryVerify)) {
        return _denied();
      }
    }
    try {
      final updated = parcel.replaceBoundary(
        boundary: Wgs84Polygon.fromVertices(command.vertices),
        source: command.source,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: command.actorMembershipId,
        occurredAt: command.occurredAt,
        horizontalAccuracyM: command.horizontalAccuracyM,
        boundaryConfidence: command.boundaryConfidence,
        note: command.note,
        sourceFileName: command.sourceFileName,
        sourceFileHash: command.sourceFileHash,
        allowVerifiedReplacement: command.confirmVerifiedReplacement,
      );

      final workflow = spatialWorkflow;
      if (workflow != null) {
        await workflow.update(
          parcel: updated,
          temporalState: SpatialTemporalState.operational,
        );
      } else {
        // Sprint 12 (D1): spatial-enabled LandParcel requires the
        // spatial workflow for boundary mutation. Silent Farm-only
        // boundary change would diverge from Spatial Core.
        //
        // A genuinely legacy parcel (spatialFeatureId == null) may
        // still use the compatibility repository path.
        if (updated.spatialFeatureId != null) {
          return LandParcelApplicationResult.failure(
            LandParcelApplicationStatus.persistenceFailed,
            'landParcel.spatial.workflowRequired',
            error: StateError(
              'Spatial-enabled LandParcel requires '
              'LandParcelSpatialSyncWorkflow for boundary update. '
              'Parcel: , '
              'spatialFeatureId: .',
            ),
          );
        }
        await repository.transaction(
          (transaction) => transaction.update(updated),
        );
      }

      return LandParcelApplicationResult.success(
        updated,
        'landParcel.boundary.replaceSuccess',
      );
    } on FormatException catch (error) {
      return _validation(error);
    } catch (error) {
      return _persistence(error);
    }
  }

  @override
  Future<LandParcelApplicationResult<LandParcel>> verifyBoundary(
    AuthorizationSubject subject,
    VerifyBoundaryCommand command,
  ) => _mutateExisting(
    subject: subject,
    farmId: command.farmId,
    parcelId: command.parcelId,
    permissions: const [PermissionCodes.fieldBoundaryVerify],
    mutation: (parcel) => parcel.verifyBoundary(
      status: command.status,
      actorMembershipId: command.actorMembershipId,
      occurredAt: command.occurredAt,
    ),
    successKey: 'landParcel.boundary.verifySuccess',
  );

  @override
  LandParcelApplicationResult<KmlImportDocument> importKmlPreview(
    AuthorizationSubject subject, {
    required String farmId,
    required String kml,
  }) {
    if (!_can(
      subject,
      ResourceContext(farmId: farmId),
      PermissionCodes.fieldGoogleEarthImport,
    )) {
      return _denied();
    }
    try {
      return LandParcelApplicationResult.success(
        interchange.importKml(kml),
        'landParcel.import.previewReady',
      );
    } catch (error) {
      return LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.interchangeFailed,
        'landParcel.import.failed',
        error: error,
      );
    }
  }

  @override
  LandParcelApplicationResult<KmlImportDocument> importKmzPreview(
    AuthorizationSubject subject, {
    required String farmId,
    required Uint8List kmz,
  }) {
    if (!_can(
      subject,
      ResourceContext(farmId: farmId),
      PermissionCodes.fieldGoogleEarthImport,
    )) {
      return _denied();
    }
    try {
      return LandParcelApplicationResult.success(
        interchange.importKmz(kmz),
        'landParcel.import.previewReady',
      );
    } catch (error) {
      return LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.interchangeFailed,
        'landParcel.import.failed',
        error: error,
      );
    }
  }

  @override
  Future<LandParcelApplicationResult<LandParcel>> applyImportedBoundary(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
    required LandParcelImportPreview preview,
    required String actorMembershipId,
    required DateTime occurredAt,
    bool confirmVerifiedReplacement = false,
    String? sourceFileName,
    String? sourceFileHash,
  }) => replaceBoundary(
    subject,
    ReplaceBoundaryCommand(
      farmId: farmId,
      parcelId: parcelId,
      vertices: preview.boundary.vertices,
      source: BoundarySource.googleEarth,
      actorMembershipId: actorMembershipId,
      occurredAt: occurredAt,
      confirmVerifiedReplacement: confirmVerifiedReplacement,
      sourceFileName: sourceFileName,
      sourceFileHash: sourceFileHash,
    ),
  );

  @override
  Future<LandParcelApplicationResult<LandParcelExport>> exportKmlKmz(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
    required LandParcelInterchangeFormat format,
  }) async {
    final resource = ResourceContext(farmId: farmId, fieldId: parcelId);
    if (!_can(subject, resource, PermissionCodes.fieldGoogleEarthExport)) {
      return _denied();
    }
    final parcel = await repository.getById(farmId: farmId, id: parcelId);
    if (parcel == null) return _notFound();
    try {
      final consistency = await boundaryConsistencyQueries?.check(parcel);
      if (consistency == LandParcelBoundaryConsistency.needsReconciliation ||
          consistency == LandParcelBoundaryConsistency.repairableLegacyIdentity) {
        return const LandParcelApplicationResult.failure(
          LandParcelApplicationStatus.validationFailed,
          'boundary.reconciliation.required',
        );
      }
      final safeCode = parcel.parcelCode.replaceAll(RegExp(r'[^\w.-]'), '_');
      return LandParcelApplicationResult.success(
        format == LandParcelInterchangeFormat.kml
            ? LandParcelExport(
                format: format,
                fileName: 'AGRICO_$safeCode.kml',
                text: interchange.exportKml(parcel),
              )
            : LandParcelExport(
                format: format,
                fileName: 'AGRICO_$safeCode.kmz',
                bytes: interchange.exportKmz(parcel),
              ),
        'landParcel.export.success',
      );
    } catch (error) {
      return LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.interchangeFailed,
        'landParcel.export.failed',
        error: error,
      );
    }
  }

  @override
  Future<LandParcelApplicationResult<LandParcel>> reconcileLegacySpatialIdentity(
    AuthorizationSubject subject, {
    required String farmId,
    required String parcelId,
  }) async {
    final resource = ResourceContext(farmId: farmId, fieldId: parcelId);
    if (!_canAll(subject, resource, [
      PermissionCodes.fieldEdit,
      PermissionCodes.fieldBoundaryVerify,
    ])) {
      return _denied();
    }
    final workflow = spatialWorkflow;
    if (workflow == null) {
      return const LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.persistenceFailed,
        'landParcel.spatial.workflowRequired',
      );
    }
    try {
      final parcel = await workflow.reconcileLegacySpatialIdentity(
        farmId: farmId,
        landParcelId: parcelId,
      );
      return LandParcelApplicationResult.success(
        parcel,
        'boundary.reconciliation.success',
      );
    } on StateError catch (error) {
      return LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.validationFailed,
        'boundary.reconciliation.manual',
        error: error,
      );
    } catch (error) {
      return _persistence(error);
    }
  }

  @override
  Future<LandParcelApplicationResult<LandUseProfile>>
      updateLandUseProfile(
    AuthorizationSubject subject,
    UpdateLandUseProfileCommand command,
  ) async {
    final resource = ResourceContext(
      farmId: command.farmId,
      fieldId: command.parcelId,
    );
    if (!_can(subject, resource, PermissionCodes.fieldEdit)) {
      return _denied();
    }

    final surveyRepository = landSurveyRepository;
    if (surveyRepository == null) {
      return const LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.persistenceFailed,
        'landUseProfile.repositoryNotConfigured',
      );
    }

    try {
      final existing = await surveyRepository.getLandUseProfile(
        command.parcelId,
      );
      final updated = LandUseProfile(
        parcelId: command.parcelId,
        landUseType: command.landUseType ??
            existing?.landUseType ??
            LandUseType.other,
        currentCondition: command.currentCondition ??
            existing?.currentCondition ??
            LandCondition.unknown,
        clearingStatus: command.clearingStatus ??
            existing?.clearingStatus ??
            ClearingStatus.unknown,
        readinessStatus: command.readinessStatus ??
            existing?.readinessStatus ??
            ReadinessStatus.unknown,
        notes: command.notes ?? existing?.notes,
        updatedAt: command.occurredAt,
        updatedBy: command.actorMembershipId,
        schemaVersion: existing?.schemaVersion ?? LandUseProfile.currentSchemaVersion,
      );
      updated.validate();
      await surveyRepository.saveLandUseProfile(updated);
      return LandParcelApplicationResult.success(
        updated,
        'landUseProfile.update.success',
      );
    } on FormatException catch (error) {
      return LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.validationFailed,
        'landUseProfile.validation.failed',
        error: error,
      );
    } catch (error) {
      return LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.persistenceFailed,
        'landUseProfile.persistence.failed',
        error: error,
      );
    }
  }

  Future<LandParcelApplicationResult<LandParcel>> _mutateExisting({
    required AuthorizationSubject subject,
    required String farmId,
    required String parcelId,
    required List<String> permissions,
    required LandParcel Function(LandParcel parcel) mutation,
    required String successKey,
  }) async {
    final resource = ResourceContext(farmId: farmId, fieldId: parcelId);
    if (!_canAll(subject, resource, permissions)) return _denied();
    final parcel = await repository.getById(farmId: farmId, id: parcelId);
    if (parcel == null) return _notFound();
    try {
      final updated = mutation(parcel);
      await repository.transaction(
        (transaction) => transaction.update(updated),
      );
      return LandParcelApplicationResult.success(updated, successKey);
    } on FormatException catch (error) {
      return _validation(error);
    } on ArgumentError catch (error) {
      return _validation(error);
    } catch (error) {
      return _persistence(error);
    }
  }

  bool _can(
    AuthorizationSubject subject,
    ResourceContext resource,
    String permission,
  ) => authorization.can(
    subject: subject,
    permission: permission,
    resource: resource,
  );

  bool _canAll(
    AuthorizationSubject subject,
    ResourceContext resource,
    Iterable<String> permissions,
  ) => permissions.every((permission) => _can(subject, resource, permission));

  static LandParcelApplicationResult<T> _denied<T>() =>
      const LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.permissionDenied,
        'error.permissionDenied',
      );

  static LandParcelApplicationResult<T> _notFound<T>() =>
      const LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.notFound,
        'landParcel.error.notFound',
      );

  static LandParcelApplicationResult<T> _validation<T>(Object error) =>
      LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.validationFailed,
        'landParcel.geometry.invalid',
        error: error,
      );

  static LandParcelApplicationResult<T> _persistence<T>(Object error) =>
      LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.persistenceFailed,
        'landParcel.persistence.failed',
        error: error,
      );
}
