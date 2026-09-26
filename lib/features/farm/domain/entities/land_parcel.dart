import 'dart:collection';

import '../geometry/wgs84_geometry.dart';

enum BoundarySource { gps, googleEarth, manual, cad, imported }

enum BoundaryVerificationStatus { draft, measured, verified, rejected }

class LandParcelBoundaryVersion {
  const LandParcelBoundaryVersion({
    required this.id,
    required this.parcelId,
    required this.version,
    required this.boundary,
    required this.centroid,
    required this.areaM2,
    required this.perimeterM,
    required this.source,
    required this.verificationStatus,
    required this.occurredAt,
    required this.actorMembershipId,
    this.horizontalAccuracyM,
    this.boundaryConfidence,
    this.note,
    this.sourceFileName,
    this.sourceFileHash,
  });

  final String id;
  final String parcelId;
  final int version;
  final Wgs84Polygon boundary;
  final Wgs84Vertex centroid;
  final double areaM2;
  final double perimeterM;
  final BoundarySource source;
  final BoundaryVerificationStatus verificationStatus;
  final double? horizontalAccuracyM;
  final double? boundaryConfidence;
  final DateTime occurredAt;
  final String actorMembershipId;
  final String? note;
  final String? sourceFileName;
  final String? sourceFileHash;

  double get areaHa => areaM2 / 10000;
}

class LandParcel {
  LandParcel._({
    required this.id,
    required this.farmId,
    required this.parcelCode,
    required this.name,
    required this.active,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    required this.schemaVersion,
    required this.boundary,
    required this.centroid,
    required this.areaM2,
    required this.perimeterM,
    required this.boundarySource,
    required this.verificationStatus,
    required this.boundaryVersion,
    required List<LandParcelBoundaryVersion> boundaryHistory,
    Map<String, Object?> legacyMetadata = const {},
    this.ownerHouseholdId,
    this.ownerDisplayName,
    this.ownerContact,
    this.horizontalAccuracyM,
    this.measuredAt,
    this.measuredBy,
    this.boundaryConfidence,
    this.spatialFeatureId,
    this.countryCode,
    this.provinceCode,
    this.districtCode,
    this.villageCode,
  }) : boundaryHistory = UnmodifiableListView(boundaryHistory),
       legacyMetadata = UnmodifiableMapView(legacyMetadata);

  factory LandParcel.create({
    required String id,
    required String farmId,
    required String parcelCode,
    required String name,
    required Wgs84Polygon boundary,
    required BoundarySource boundarySource,
    required BoundaryVerificationStatus verificationStatus,
    required String actorMembershipId,
    required DateTime occurredAt,
    String? ownerHouseholdId,
    String? ownerDisplayName,
    String? ownerContact,
    bool active = true,
    double? horizontalAccuracyM,
    double? boundaryConfidence,
    String? note,
    Map<String, Object?> legacyMetadata = const {},
    String? spatialFeatureId,
    String? countryCode,
    String? provinceCode,
    String? districtCode,
    String? villageCode,
  }) {
    _requireIdentity(id, farmId, parcelCode, name, actorMembershipId);
    _requireOptionalText(spatialFeatureId, 'spatialFeatureId');
    _requireOptionalText(ownerHouseholdId, 'ownerHouseholdId');
    _requireOptionalText(ownerDisplayName, 'ownerDisplayName');
    _requireOptionalText(ownerContact, 'ownerContact');
    _requireOptionalText(countryCode, 'countryCode');
    _requireOptionalText(provinceCode, 'provinceCode');
    _requireOptionalText(districtCode, 'districtCode');
    _requireOptionalText(villageCode, 'villageCode');
    final metrics = const Wgs84GeometryService().measure(boundary);
    final version = _buildVersion(
      parcelId: id,
      version: 1,
      boundary: boundary,
      metrics: metrics,
      source: boundarySource,
      verificationStatus: verificationStatus,
      horizontalAccuracyM: horizontalAccuracyM,
      boundaryConfidence: boundaryConfidence,
      actorMembershipId: actorMembershipId,
      occurredAt: occurredAt,
      note: note,
    );
    return LandParcel._(
      id: id,
      farmId: farmId,
      parcelCode: parcelCode,
      name: name,
      ownerHouseholdId: ownerHouseholdId,
      ownerDisplayName: ownerDisplayName,
      ownerContact: ownerContact,
      active: active,
      spatialFeatureId: spatialFeatureId,
      countryCode: countryCode,
      provinceCode: provinceCode,
      districtCode: districtCode,
      villageCode: villageCode,
      createdAt: occurredAt,
      createdBy: actorMembershipId,
      updatedAt: occurredAt,
      updatedBy: actorMembershipId,
      schemaVersion: currentSchemaVersion,
      boundary: boundary,
      centroid: metrics.centroid,
      areaM2: metrics.areaM2,
      perimeterM: metrics.perimeterM,
      boundarySource: boundarySource,
      horizontalAccuracyM: horizontalAccuracyM,
      measuredAt: occurredAt,
      measuredBy: actorMembershipId,
      verificationStatus: verificationStatus,
      boundaryConfidence: boundaryConfidence,
      boundaryVersion: 1,
      boundaryHistory: [version],
      legacyMetadata: legacyMetadata,
    );
  }

  factory LandParcel.rehydrate({
    required String id,
    required String farmId,
    required String parcelCode,
    required String name,
    required bool active,
    required DateTime createdAt,
    required String createdBy,
    required DateTime updatedAt,
    required String updatedBy,
    required int schemaVersion,
    required Wgs84Polygon boundary,
    required Wgs84Vertex centroid,
    required double areaM2,
    required double perimeterM,
    required BoundarySource boundarySource,
    required BoundaryVerificationStatus verificationStatus,
    required int boundaryVersion,
    required List<LandParcelBoundaryVersion> boundaryHistory,
    String? ownerHouseholdId,
    String? ownerDisplayName,
    String? ownerContact,
    double? horizontalAccuracyM,
    DateTime? measuredAt,
    String? measuredBy,
    double? boundaryConfidence,
    Map<String, Object?> legacyMetadata = const {},
    String? spatialFeatureId,
    String? countryCode,
    String? provinceCode,
    String? districtCode,
    String? villageCode,
  }) {
    _requireIdentity(id, farmId, parcelCode, name, createdBy);
    _requireOptionalText(spatialFeatureId, 'spatialFeatureId');
    _requireOptionalText(ownerContact, 'ownerContact');
    _requireOptionalText(countryCode, 'countryCode');
    _requireOptionalText(provinceCode, 'provinceCode');
    _requireOptionalText(districtCode, 'districtCode');
    _requireOptionalText(villageCode, 'villageCode');
    if (schemaVersion <= 0 ||
        boundaryVersion <= 0 ||
        areaM2 <= 0 ||
        perimeterM <= 0) {
      throw const FormatException('Land parcel persisted values are invalid.');
    }
    final matchingVersion = boundaryHistory.any(
      (item) => item.parcelId == id && item.version == boundaryVersion,
    );
    if (!matchingVersion) {
      throw const FormatException(
        'Current boundary version is missing from immutable history.',
      );
    }
    return LandParcel._(
      id: id,
      farmId: farmId,
      parcelCode: parcelCode,
      name: name,
      ownerHouseholdId: ownerHouseholdId,
      ownerDisplayName: ownerDisplayName,
      ownerContact: ownerContact,
      active: active,
      spatialFeatureId: spatialFeatureId,
      countryCode: countryCode,
      provinceCode: provinceCode,
      districtCode: districtCode,
      villageCode: villageCode,
      createdAt: createdAt,
      createdBy: createdBy,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      schemaVersion: schemaVersion,
      boundary: boundary,
      centroid: centroid,
      areaM2: areaM2,
      perimeterM: perimeterM,
      boundarySource: boundarySource,
      horizontalAccuracyM: horizontalAccuracyM,
      measuredAt: measuredAt,
      measuredBy: measuredBy,
      verificationStatus: verificationStatus,
      boundaryConfidence: boundaryConfidence,
      boundaryVersion: boundaryVersion,
      boundaryHistory: boundaryHistory,
      legacyMetadata: legacyMetadata,
    );
  }

  static const currentSchemaVersion = 2;

  final String id;
  final String farmId;
  final String parcelCode;
  final String name;
  final String? ownerHouseholdId;
  final String? ownerDisplayName;
  final bool active;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
  final int schemaVersion;
  final Wgs84Polygon boundary;
  final Wgs84Vertex centroid;
  final double areaM2;
  final double perimeterM;
  final BoundarySource boundarySource;
  final double? horizontalAccuracyM;
  final DateTime? measuredAt;
  final String? measuredBy;
  final BoundaryVerificationStatus verificationStatus;
  final double? boundaryConfidence;
  final int boundaryVersion;
  final UnmodifiableListView<LandParcelBoundaryVersion> boundaryHistory;
  final UnmodifiableMapView<String, Object?> legacyMetadata;

  /// Reference to the stable Spatial Core identity.
  ///
  /// Sprint 6A: nullable for legacy rehydrate compatibility.
  /// Semantic target: required for new records (SpatialFeature.id).
  final String? spatialFeatureId;

  /// Administrative identifiers (nullable for legacy records).
  final String? countryCode;
  final String? provinceCode;
  final String? districtCode;
  final String? villageCode;

  /// Optional owner contact.
  final String? ownerContact;

  double get areaHa => areaM2 / 10000;

  LandParcel updateMetadata({
    String? parcelCode,
    String? name,
    String? ownerHouseholdId,
    String? ownerDisplayName,
    String? ownerContact,
    bool? active,
    String? countryCode,
    String? provinceCode,
    String? districtCode,
    String? villageCode,
    required String actorMembershipId,
    required DateTime occurredAt,
  }) {
    final nextCode = parcelCode ?? this.parcelCode;
    final nextName = name ?? this.name;
    _requireIdentity(id, farmId, nextCode, nextName, actorMembershipId);
    _requireOptionalText(ownerHouseholdId, 'ownerHouseholdId');
    _requireOptionalText(ownerDisplayName, 'ownerDisplayName');
    _requireOptionalText(ownerContact, 'ownerContact');
    _requireOptionalText(countryCode, 'countryCode');
    _requireOptionalText(provinceCode, 'provinceCode');
    _requireOptionalText(districtCode, 'districtCode');
    _requireOptionalText(villageCode, 'villageCode');
    return _copyWith(
      parcelCode: nextCode,
      name: nextName,
      ownerHouseholdId: ownerHouseholdId ?? this.ownerHouseholdId,
      ownerDisplayName: ownerDisplayName ?? this.ownerDisplayName,
      ownerContact: ownerContact ?? this.ownerContact,
      active: active ?? this.active,
      countryCode: countryCode ?? this.countryCode,
      provinceCode: provinceCode ?? this.provinceCode,
      districtCode: districtCode ?? this.districtCode,
      villageCode: villageCode ?? this.villageCode,
      updatedAt: occurredAt,
      updatedBy: actorMembershipId,
    );
  }

  LandParcel verifyBoundary({
    required BoundaryVerificationStatus status,
    required String actorMembershipId,
    required DateTime occurredAt,
  }) {
    if (status != BoundaryVerificationStatus.verified &&
        status != BoundaryVerificationStatus.rejected) {
      throw ArgumentError.value(
        status,
        'status',
        'Verification can only resolve to verified or rejected.',
      );
    }
    return _copyWith(
      verificationStatus: status,
      updatedAt: occurredAt,
      updatedBy: actorMembershipId,
    );
  }

  LandParcel replaceBoundary({
    required Wgs84Polygon boundary,
    required BoundarySource source,
    required BoundaryVerificationStatus verificationStatus,
    required String actorMembershipId,
    required DateTime occurredAt,
    double? horizontalAccuracyM,
    double? boundaryConfidence,
    String? note,
    String? sourceFileName,
    String? sourceFileHash,
    bool allowVerifiedReplacement = false,
  }) {
    if (this.verificationStatus == BoundaryVerificationStatus.verified &&
        !allowVerifiedReplacement) {
      throw StateError(
        'A verified boundary requires explicit replacement confirmation.',
      );
    }
    final metrics = const Wgs84GeometryService().measure(boundary);
    final nextVersion = boundaryVersion + 1;
    final history = List<LandParcelBoundaryVersion>.of(boundaryHistory)
      ..add(
        _buildVersion(
          parcelId: id,
          version: nextVersion,
          boundary: boundary,
          metrics: metrics,
          source: source,
          verificationStatus: verificationStatus,
          horizontalAccuracyM: horizontalAccuracyM,
          boundaryConfidence: boundaryConfidence,
          actorMembershipId: actorMembershipId,
          occurredAt: occurredAt,
          note: note,
          sourceFileName: sourceFileName,
          sourceFileHash: sourceFileHash,
        ),
      );
    return LandParcel._(
      id: id,
      farmId: farmId,
      parcelCode: parcelCode,
      name: name,
      ownerHouseholdId: ownerHouseholdId,
      ownerDisplayName: ownerDisplayName,
      ownerContact: ownerContact,
      active: active,
      spatialFeatureId: spatialFeatureId,
      countryCode: countryCode,
      provinceCode: provinceCode,
      districtCode: districtCode,
      villageCode: villageCode,
      createdAt: createdAt,
      createdBy: createdBy,
      updatedAt: occurredAt,
      updatedBy: actorMembershipId,
      schemaVersion: schemaVersion,
      boundary: boundary,
      centroid: metrics.centroid,
      areaM2: metrics.areaM2,
      perimeterM: metrics.perimeterM,
      boundarySource: source,
      horizontalAccuracyM: horizontalAccuracyM,
      measuredAt: occurredAt,
      measuredBy: actorMembershipId,
      verificationStatus: verificationStatus,
      boundaryConfidence: boundaryConfidence,
      boundaryVersion: nextVersion,
      boundaryHistory: history,
      legacyMetadata: legacyMetadata,
    );
  }

  LandParcel restoreBoundaryVersion({
    required int version,
    required String actorMembershipId,
    required DateTime occurredAt,
    bool allowVerifiedReplacement = false,
  }) {
    final historical = boundaryHistory.where((item) => item.version == version);
    if (historical.isEmpty) {
      throw ArgumentError.value(
        version,
        'version',
        'Boundary version not found.',
      );
    }
    return replaceBoundary(
      boundary: historical.single.boundary,
      source: historical.single.source,
      verificationStatus: historical.single.verificationStatus,
      actorMembershipId: actorMembershipId,
      occurredAt: occurredAt,
      horizontalAccuracyM: historical.single.horizontalAccuracyM,
      boundaryConfidence: historical.single.boundaryConfidence,
      note: 'Restored from version $version',
      allowVerifiedReplacement: allowVerifiedReplacement,
    );
  }

  /// Establishes the stable spatial identity of this LandParcel exactly once.
  ///
  /// Sprint 10: this is the canonical way to link a legacy LandParcel
  /// (spatialFeatureId == null) to a SpatialFeature. Once established,
  /// spatialFeatureId is immutable.
  ///
  /// Rules:
  /// - Blank/whitespace-only ID is rejected.
  /// - null -> X: establishes identity (returns new instance).
  /// - X -> X: idempotent (returns instance with same identity).
  /// - X -> Y: rejected with StateError.
  LandParcel assignSpatialFeatureId(String spatialFeatureId) {
    final trimmed = spatialFeatureId.trim();
    if (trimmed.isEmpty) {
      throw const FormatException(
        'Land parcel spatialFeatureId cannot be blank.',
      );
    }

    final current = this.spatialFeatureId;
    if (current == null) {
      return _copyWith(spatialFeatureId: trimmed);
    }

    if (current == trimmed) {
      return this;
    }

    throw StateError(
      'Land parcel spatialFeatureId is immutable once established. '
      'Current: , attempted: .',
    );
  }

  LandParcel _copyWith({
    String? parcelCode,
    String? name,
    String? ownerHouseholdId,
    String? ownerDisplayName,
    String? ownerContact,
    bool? active,
    DateTime? updatedAt,
    String? updatedBy,
    BoundaryVerificationStatus? verificationStatus,
    String? spatialFeatureId,
    String? countryCode,
    String? provinceCode,
    String? districtCode,
    String? villageCode,
  }) => LandParcel._(
    id: id,
    farmId: farmId,
    parcelCode: parcelCode ?? this.parcelCode,
    name: name ?? this.name,
    ownerHouseholdId: ownerHouseholdId ?? this.ownerHouseholdId,
    ownerDisplayName: ownerDisplayName ?? this.ownerDisplayName,
    ownerContact: ownerContact ?? this.ownerContact,
    active: active ?? this.active,
    spatialFeatureId: spatialFeatureId ?? this.spatialFeatureId,
    countryCode: countryCode ?? this.countryCode,
    provinceCode: provinceCode ?? this.provinceCode,
    districtCode: districtCode ?? this.districtCode,
    villageCode: villageCode ?? this.villageCode,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    schemaVersion: schemaVersion,
    boundary: boundary,
    centroid: centroid,
    areaM2: areaM2,
    perimeterM: perimeterM,
    boundarySource: boundarySource,
    horizontalAccuracyM: horizontalAccuracyM,
    measuredAt: measuredAt,
    measuredBy: measuredBy,
    verificationStatus: verificationStatus ?? this.verificationStatus,
    boundaryConfidence: boundaryConfidence,
    boundaryVersion: boundaryVersion,
    boundaryHistory: boundaryHistory,
    legacyMetadata: legacyMetadata,
  );

  static LandParcelBoundaryVersion _buildVersion({
    required String parcelId,
    required int version,
    required Wgs84Polygon boundary,
    required Wgs84PolygonMetrics metrics,
    required BoundarySource source,
    required BoundaryVerificationStatus verificationStatus,
    required String actorMembershipId,
    required DateTime occurredAt,
    double? horizontalAccuracyM,
    double? boundaryConfidence,
    String? note,
    String? sourceFileName,
    String? sourceFileHash,
  }) => LandParcelBoundaryVersion(
    id: '$parcelId-boundary-$version',
    parcelId: parcelId,
    version: version,
    boundary: boundary,
    centroid: metrics.centroid,
    areaM2: metrics.areaM2,
    perimeterM: metrics.perimeterM,
    source: source,
    verificationStatus: verificationStatus,
    horizontalAccuracyM: horizontalAccuracyM,
    boundaryConfidence: boundaryConfidence,
    occurredAt: occurredAt,
    actorMembershipId: actorMembershipId,
    note: note,
    sourceFileName: sourceFileName,
    sourceFileHash: sourceFileHash,
  );

  static void _requireIdentity(
    String id,
    String farmId,
    String parcelCode,
    String name,
    String actorMembershipId,
  ) {
    if ([
      id,
      farmId,
      parcelCode,
      name,
      actorMembershipId,
    ].any((value) => value.trim().isEmpty)) {
      throw const FormatException(
        'Land parcel identity fields cannot be empty.',
      );
    }
  }

  static void _requireOptionalText(String? value, String fieldName) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException(
        'Land parcel  cannot be blank when provided.',
      );
    }
  }
}
