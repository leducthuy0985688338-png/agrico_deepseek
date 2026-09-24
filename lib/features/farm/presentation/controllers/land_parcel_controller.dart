import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../core/permissions/authorization.dart';
import '../../application/land_parcel_boundary_consistency_queries.dart';
import '../../application/land_parcel_application_service.dart';
import '../../application/land_parcel_use_cases.dart';
import '../../data/interchange/kml_interchange.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../../domain/repositories/land_parcel_repository.dart';
import '../../domain/repositories/land_survey_repository.dart';

enum ParcelPresentationPhase {
  initial,
  loading,
  loaded,
  saving,
  success,
  validationError,
  permissionDenied,
  persistenceError,
}

class LandParcelViewData {
  const LandParcelViewData({
    required this.parcel,
    this.household,
    this.landUse,
    this.crops = const [],
    this.surveys = const [],
    this.attachments = const [],
    this.boundaryConsistency = LandParcelBoundaryConsistency.unlinked,
    this.boundaryIssue,
  });
  final LandParcel parcel;
  final Household? household;
  final LandUseProfile? landUse;
  final List<CropRecord> crops;
  final List<LandParcelSurvey> surveys;
  final List<ParcelAttachment> attachments;
  final LandParcelBoundaryConsistency boundaryConsistency;
  final LandParcelBoundaryIssue? boundaryIssue;
  String get village => household?.administrativeLocation.villageName ?? '';
  String get owner =>
      household?.headOfHouseholdName ?? parcel.ownerDisplayName ?? '';
  String get cropSummary => crops.map((value) => value.cropType).join(', ');
}

abstract interface class ExternalFileOpener {
  Future<bool> open({required String fileName, required Uint8List bytes});
}

abstract interface class GoogleEarthOpener {
  Future<bool> openInGoogleEarth({
    required String fileName,
    required Uint8List bytes,
  });
}

class LandParcelController extends ChangeNotifier {
  LandParcelController({
    required this.subject,
    required this.parcels,
    required this.surveys,
    required this.createLandParcel,
    required this.updateMetadata,
    required this.completeGpsMeasurement,
    required this.verifyBoundary,
    required this.importPreview,
    required this.applyImportedBoundary,
    required this.exportKmlKmz,
    this.authorization = const AuthorizationService(),
    this.fileOpener,
    this.googleEarthOpener,
    this.boundaryConsistencyQueries,
    this.reconcileLegacySpatialIdentity,
  });

  final AuthorizationSubject subject;
  final LandParcelRepository parcels;
  final LandSurveyRepository surveys;
  final CreateLandParcel createLandParcel;
  final UpdateLandParcelMetadata updateMetadata;
  final CompleteGpsMeasurement completeGpsMeasurement;
  final VerifyBoundary verifyBoundary;
  final ImportKmlKmzPreview importPreview;
  final ApplyImportedBoundary applyImportedBoundary;
  final ExportKmlKmz exportKmlKmz;
  final AuthorizationService authorization;
  final ExternalFileOpener? fileOpener;
  final GoogleEarthOpener? googleEarthOpener;
  final LandParcelBoundaryConsistencyQueries? boundaryConsistencyQueries;
  final ReconcileLegacySpatialIdentity? reconcileLegacySpatialIdentity;

  ParcelPresentationPhase phase = ParcelPresentationPhase.initial;
  String? messageKey;
  List<LandParcelViewData> items = const [];
  LandParcelViewData? detail;
  KmlImportDocument? previewDocument;
  String search = '';
  bool? activeFilter;
  BoundaryVerificationStatus? verificationFilter;
  LandParcelBoundaryConsistency? boundaryConsistencyFilter;
  String? villageFilter;

  bool can(String permission, {String? parcelId}) => authorization.can(
    subject: subject,
    permission: permission,
    resource: ResourceContext(farmId: subject.farmId, fieldId: parcelId),
  );

  List<LandParcelViewData> get visibleItems => items
      .where((item) {
        final query = search.trim().toLowerCase();
        return (query.isEmpty ||
                item.parcel.parcelCode.toLowerCase().contains(query) ||
                item.parcel.name.toLowerCase().contains(query) ||
                item.owner.toLowerCase().contains(query)) &&
            (activeFilter == null || item.parcel.active == activeFilter) &&
            (verificationFilter == null ||
                item.parcel.verificationStatus == verificationFilter) &&
            (boundaryConsistencyFilter == null ||
                item.boundaryConsistency == boundaryConsistencyFilter) &&
            (villageFilter == null || item.village == villageFilter);
      })
      .toList(growable: false);

  Future<void> loadList() async {
    _phase(ParcelPresentationPhase.loading);
    try {
      final source = await parcels.listByFarm(
        subject.farmId,
        includeInactive: true,
      );
      final households = {
        for (final value in await surveys.listHouseholds(subject.farmId))
          value.id: value,
      };
      final loaded = <LandParcelViewData>[];
      for (final parcel in source) {
        if (!can(PermissionCodes.fieldView, parcelId: parcel.id)) continue;
        loaded.add(
          LandParcelViewData(
            parcel: parcel,
            boundaryConsistency:
                await boundaryConsistencyQueries?.check(parcel) ??
                LandParcelBoundaryConsistency.unlinked,
            household: households[parcel.ownerHouseholdId],
            crops: await surveys.listCrops(parcel.id),
          ),
        );
      }
      items = List.unmodifiable(loaded);
      _phase(ParcelPresentationPhase.loaded);
    } catch (_) {
      _phase(ParcelPresentationPhase.persistenceError, 'parcel.list.error');
    }
  }

  Future<void> loadDetail(String parcelId) async {
    _phase(ParcelPresentationPhase.loading);
    if (!can(PermissionCodes.fieldView, parcelId: parcelId)) {
      _phase(
        ParcelPresentationPhase.permissionDenied,
        'error.permissionDenied',
      );
      return;
    }
    try {
      final parcel = await parcels.getById(
        farmId: subject.farmId,
        id: parcelId,
      );
      if (parcel == null) {
        _phase(
          ParcelPresentationPhase.persistenceError,
          'landParcel.error.notFound',
        );
        return;
      }
      final diagnosis = await boundaryConsistencyQueries?.diagnose(parcel);
      detail = LandParcelViewData(
        parcel: parcel,
        boundaryConsistency: diagnosis?.consistency ??
            LandParcelBoundaryConsistency.unlinked,
        boundaryIssue: diagnosis?.issue,
        household: parcel.ownerHouseholdId == null
            ? null
            : await surveys.getHousehold(parcel.ownerHouseholdId!),
        landUse: await surveys.getLandUseProfile(parcel.id),
        crops: await surveys.listCrops(parcel.id, includeInactive: true),
        surveys: await surveys.listSurveys(parcel.id),
        attachments: await surveys.listAttachments(parcel.id),
      );
      _phase(ParcelPresentationPhase.loaded);
    } catch (_) {
      _phase(ParcelPresentationPhase.persistenceError, 'parcel.detail.error');
    }
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  void setActiveFilter(bool? value) {
    activeFilter = value;
    notifyListeners();
  }

  void setVerificationFilter(BoundaryVerificationStatus? value) {
    verificationFilter = value;
    notifyListeners();
  }

  void setBoundaryConsistencyFilter(LandParcelBoundaryConsistency? value) {
    boundaryConsistencyFilter = value;
    notifyListeners();
  }

  void setVillageFilter(String? value) {
    villageFilter = value;
    notifyListeners();
  }

  Future<LandParcelApplicationResult<LandParcel>> create({
    required String id,
    required String parcelCode,
    required String name,
    required List<Wgs84Vertex> vertices,
    required BoundarySource source,
    String? ownerHouseholdId,
    String? ownerDisplayName,
    double? horizontalAccuracyM,
    double? boundaryConfidence,
    Map<String, Object?> legacyMetadata = const {},
  }) async {
    if (vertices.length < 3) {
      return const LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.validationFailed,
        'landParcel.geometry.invalid',
      );
    }

    _phase(ParcelPresentationPhase.saving);

    final result = await createLandParcel(
      subject,
      CreateLandParcelCommand(
        id: id,
        farmId: subject.farmId,
        parcelCode: parcelCode,
        name: name,
        vertices: vertices,
        source: source,
        actorMembershipId: subject.membershipId,
        occurredAt: DateTime.now().toUtc(),
        ownerHouseholdId: ownerHouseholdId,
        ownerDisplayName: ownerDisplayName,
        horizontalAccuracyM: horizontalAccuracyM,
        boundaryConfidence: boundaryConfidence,
        legacyMetadata: legacyMetadata,
      ),
    );

    _result(result);

    if (result.isSuccess && result.value != null) {
      await loadList();
      await loadDetail(result.value!.id);
    }

    return result;
  }

  Future<LandParcelApplicationResult<LandParcel>> update({
    required String parcelId,
    required String parcelCode,
    required String name,
    String? ownerHouseholdId,
    String? ownerDisplayName,
    required bool active,
  }) async {
    _phase(ParcelPresentationPhase.saving);

    final result = await updateMetadata(
      subject,
      UpdateLandParcelMetadataCommand(
        farmId: subject.farmId,
        parcelId: parcelId,
        actorMembershipId: subject.membershipId,
        occurredAt: DateTime.now().toUtc(),
        parcelCode: parcelCode,
        name: name,
        ownerHouseholdId: ownerHouseholdId,
        ownerDisplayName: ownerDisplayName,
        active: active,
      ),
    );

    _result(result);

    if (result.isSuccess) {
      await loadList();
      await loadDetail(parcelId);
    }

    return result;
  }

  Future<LandParcelApplicationResult<LandParcel>> applyGps({
    required String parcelId,
    required List<Wgs84Vertex> vertices,
    bool confirmVerifiedReplacement = false,
  }) async {
    if (vertices.length < 3) {
      return const LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.validationFailed,
        'landParcel.geometry.invalid',
      );
    }
    _phase(ParcelPresentationPhase.saving);
    final result = await completeGpsMeasurement.replace(
      subject,
      farmId: subject.farmId,
      parcelId: parcelId,
      completedVertices: vertices,
      actorMembershipId: subject.membershipId,
      occurredAt: DateTime.now().toUtc(),
      confirmVerifiedReplacement: confirmVerifiedReplacement,
    );
    _result(result);
    if (result.isSuccess) await loadDetail(parcelId);
    return result;
  }

  Future<LandParcelApplicationResult<LandParcel>> verify({
    required String parcelId,
    BoundaryVerificationStatus status = BoundaryVerificationStatus.verified,
  }) async {
    _phase(ParcelPresentationPhase.saving);
    final result = await verifyBoundary(
      subject,
      VerifyBoundaryCommand(
        farmId: subject.farmId,
        parcelId: parcelId,
        status: status,
        actorMembershipId: subject.membershipId,
        occurredAt: DateTime.now().toUtc(),
      ),
    );
    _result(result);
    if (result.isSuccess) await loadDetail(parcelId);
    return result;
  }

  LandParcelApplicationResult<KmlImportDocument> previewKml(String source) {
    final result = importPreview.kml(
      subject,
      farmId: subject.farmId,
      source: source,
    );
    previewDocument = result.value;
    _result(result);
    return result;
  }

  LandParcelApplicationResult<KmlImportDocument> previewKmz(Uint8List source) {
    final result = importPreview.kmz(
      subject,
      farmId: subject.farmId,
      source: source,
    );
    previewDocument = result.value;
    _result(result);
    return result;
  }

  Future<LandParcelApplicationResult<LandParcel>> confirmImport({
    required String parcelId,
    required LandParcelImportPreview preview,
    bool confirmVerifiedReplacement = false,
  }) async {
    _phase(ParcelPresentationPhase.saving);
    final result = await applyImportedBoundary(
      subject,
      farmId: subject.farmId,
      parcelId: parcelId,
      preview: preview,
      actorMembershipId: subject.membershipId,
      occurredAt: DateTime.now().toUtc(),
      confirmVerifiedReplacement: confirmVerifiedReplacement,
    );
    _result(result);
    if (result.isSuccess) await loadDetail(parcelId);
    return result;
  }

  Future<LandParcelApplicationResult<LandParcelExport>> export(
    String parcelId,
    LandParcelInterchangeFormat format,
  ) async {
    _phase(ParcelPresentationPhase.saving);
    final result = await exportKmlKmz(
      subject,
      farmId: subject.farmId,
      parcelId: parcelId,
      format: format,
    );
    _result(result);
    return result;
  }

  Future<LandParcelApplicationResult<LandParcel>> reconcileLegacyIdentity(
    String parcelId,
  ) async {
    final action = reconcileLegacySpatialIdentity;
    if (action == null) {
      return const LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.persistenceFailed,
        'landParcel.spatial.workflowRequired',
      );
    }
    _phase(ParcelPresentationPhase.saving);
    final result = await action(
      subject,
      farmId: subject.farmId,
      parcelId: parcelId,
    );
    _result(result);
    if (result.isSuccess) await loadDetail(parcelId);
    return result;
  }

  Future<bool> openInGoogleEarth(String parcelId) async {
    final opener = googleEarthOpener;
    if (opener == null) {
      _phase(
        ParcelPresentationPhase.persistenceError,
        'googleEarth.openUnavailable',
      );
      return false;
    }
    final result = await export(parcelId, LandParcelInterchangeFormat.kmz);
    final value = result.value;
    if (!result.isSuccess || value == null) return false;
    final bytes =
        value.bytes ?? Uint8List.fromList(utf8.encode(value.text ?? ''));
    final opened = await opener.openInGoogleEarth(
      fileName: value.fileName,
      bytes: bytes,
    );
    _phase(
      opened
          ? ParcelPresentationPhase.success
          : ParcelPresentationPhase.persistenceError,
      opened ? 'googleEarth.openSuccess' : 'googleEarth.openUnavailable',
    );
    return opened;
  }

  Future<bool> exportAndOpen(
    String parcelId,
    LandParcelInterchangeFormat format,
  ) async {
    final opener = fileOpener;
    if (opener == null) {
      _phase(ParcelPresentationPhase.persistenceError, 'export.unavailable');
      return false;
    }
    final result = await export(parcelId, format);
    final value = result.value;
    if (!result.isSuccess || value == null) return false;
    final bytes =
        value.bytes ?? Uint8List.fromList(utf8.encode(value.text ?? ''));
    final opened = await opener.open(fileName: value.fileName, bytes: bytes);
    _phase(
      opened
          ? ParcelPresentationPhase.success
          : ParcelPresentationPhase.persistenceError,
      opened ? 'landParcel.export.success' : 'export.unavailable',
    );
    return opened;
  }

  void _result(LandParcelApplicationResult<Object?> result) {
    messageKey = result.messageKey;
    phase = switch (result.status) {
      LandParcelApplicationStatus.success => ParcelPresentationPhase.success,
      LandParcelApplicationStatus.permissionDenied =>
        ParcelPresentationPhase.permissionDenied,
      LandParcelApplicationStatus.validationFailed ||
      LandParcelApplicationStatus.confirmationRequired =>
        ParcelPresentationPhase.validationError,
      _ => ParcelPresentationPhase.persistenceError,
    };
    notifyListeners();
  }

  void _phase(ParcelPresentationPhase value, [String? key]) {
    phase = value;
    messageKey = key;
    notifyListeners();
  }
}
