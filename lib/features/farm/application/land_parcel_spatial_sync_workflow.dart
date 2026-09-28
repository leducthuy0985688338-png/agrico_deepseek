import 'package:sqflite/sqflite.dart';
import '../../../core/identity/domain/parcel_number_allocator.dart';
import '../../../core/identity/data/sqlite_scoped_parcel_number_allocator.dart';

import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/identity/spatial_identity_generator.dart';
import '../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../data/adapters/land_parcel_spatial_projection.dart';
import '../data/adapters/land_parcel_spatial_transaction.dart';
import '../data/local/sqlite_parcel_land_history_repository.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/entities/parcel_land_history.dart';
import '../domain/geometry/parcel_boundary_splitter.dart';
import '../domain/geometry/wgs84_geometry.dart';
import '../domain/entities/land_survey.dart';
import '../domain/entities/land_parcel_spatial_link.dart';
import '../domain/repositories/land_parcel_repository.dart';
import '../domain/repositories/land_survey_repository.dart';
import '../domain/repositories/land_parcel_spatial_link_repository.dart';
import '../../../core/spatial/data/spatial_persistence_composition.dart';
import 'land_parcel_boundary_consistency_queries.dart';

/// Atomically synchronizes one LandParcel state with its stable Spatial Core
/// projection.
///
/// Creation establishes the persistent LandParcel-to-SpatialFeature identity.
/// Updates resolve SpatialFeature identity from that persisted association
/// rather than trusting a caller-supplied SpatialFeature id.
///
/// Spatial identities are generated internally while revision numbers are
/// derived from persisted Spatial Core state.
class LandParcelSpatialSyncWorkflow {
  const LandParcelSpatialSyncWorkflow({
    required this.transaction,
    required this.projection,
    required this.identityGenerator,
  });

  final LandParcelSpatialTransaction transaction;
  final LandParcelSpatialProjection projection;
  final SpatialIdentityGenerator identityGenerator;

  /// Creates two child parcels, their spatial identities, and their lineage
  /// in one SQLite transaction. The source boundary and identity are retained.
  Future<List<LandParcel>> subdivide({
    required String farmId,
    required String sourceParcelId,
    required String villageId,
    required int expectedBoundaryVersion,
    required Wgs84Vertex cutStart,
    required Wgs84Vertex cutEnd,
    List<Wgs84Vertex> cutWaypoints = const [],
    required String firstName,
    required String secondName,
    required String actorMembershipId,
    required DateTime occurredAt,
  }) async {
    if (firstName.trim().isEmpty || secondName.trim().isEmpty ||
        villageId.trim().isEmpty) {
      throw const FormatException('Two names and a catalogued village are required.');
    }
    final childIds = [identityGenerator.newId('land-parcel'),
      identityGenerator.newId('land-parcel')];
    final linkIds = [identityGenerator.newId('spatial-link'),
      identityGenerator.newId('spatial-link')];
    final featureIds = [identityGenerator.newId('spatial-feature'),
      identityGenerator.newId('spatial-feature')];
    final revisionIds = [identityGenerator.newId('spatial-revision'),
      identityGenerator.newId('spatial-revision')];
    final derivationIds = [identityGenerator.newId('derivation'),
      identityGenerator.newId('derivation')];
    Transaction? scopedTransaction;
    return transaction.run<List<LandParcel>>((parcels, links, spatial) async {
      final tx = scopedTransaction!;
      final source = await parcels.getById(farmId: farmId, id: sourceParcelId);
      if (source == null || !source.active ||
          source.boundaryVersion != expectedBoundaryVersion ||
          source.countryCode == null || source.provinceCode == null ||
          source.districtCode == null || source.villageCode == null) {
        throw StateError('Source parcel changed or has no catalogued location.');
      }
      if (source.spatialFeatureId == null ||
          await LandParcelBoundaryConsistencyQueries(
            links: links, features: spatial.featureRepository,
            revisions: spatial.revisionRepository,
          ).check(source) != LandParcelBoundaryConsistency.consistent) {
        throw StateError('Source parcel boundary needs reconciliation.');
      }
      final existingSplit = await tx.query(
        SqliteParcelLandHistoryRepository.derivationsTable,
        columns: ['id'], where: 'farm_id = ? AND source_parcel_id = ? '
            'AND kind = ?', whereArgs: [farmId, source.id,
              ParcelDerivationKind.subdivision.name], limit: 1);
      if (existingSplit.isNotEmpty) {
        throw StateError('Source parcel has already been subdivided.');
      }
      final location = await tx.rawQuery('''
        SELECT v.id FROM agrico_administrative_units v
        JOIN agrico_administrative_units d ON d.id = v.parent_id
        JOIN agrico_administrative_units p ON p.id = d.parent_id
        JOIN agrico_administrative_units c ON c.id = p.parent_id
        WHERE v.id = ? AND v.level = 'village' AND v.active = 1
          AND d.active = 1 AND p.active = 1 AND c.active = 1
          AND v.code = ? AND d.code = ? AND p.code = ? AND c.code = ?
      ''', [villageId, source.villageCode, source.districtCode,
        source.provinceCode, source.countryCode]);
      if (location.length != 1) {
        throw const FormatException('Parcel village does not match the catalog.');
      }
      final boundaries = const ParcelBoundarySplitter()
          .splitAlongPath(source.boundary,
            [cutStart, ...cutWaypoints, cutEnd]);
      final numbers = SqliteScopedParcelNumberAllocator(tx);
      final children = <LandParcel>[];
      for (var index = 0; index < 2; index++) {
        final child = await numbers.saveLocationParcel(
          farmId: farmId, villageId: villageId,
          countryCode: source.countryCode!,
          provinceCode: source.provinceCode!,
          districtCode: source.districtCode!,
          villageCode: source.villageCode!,
          save: (code) async => LandParcel.create(
            id: childIds[index], farmId: farmId, parcelCode: code,
            name: index == 0 ? firstName.trim() : secondName.trim(),
            boundary: boundaries[index], boundarySource: BoundarySource.manual,
            verificationStatus: BoundaryVerificationStatus.draft,
            actorMembershipId: actorMembershipId, occurredAt: occurredAt,
            countryCode: source.countryCode,
            provinceCode: source.provinceCode,
            districtCode: source.districtCode,
            villageCode: source.villageCode,
          ),
        );
        await createScoped(
          parcels: parcels, links: links, spatial: spatial,
          parcel: child, temporalState: SpatialTemporalState.underConstruction,
          spatialLinkId: linkIds[index],
          spatialFeatureId: featureIds[index],
          spatialRevisionId: revisionIds[index],
        );
        children.add(child.assignSpatialFeatureId(featureIds[index]));
        await SqliteParcelLandHistoryRepository.linkScoped(tx,
          ParcelDerivation(
            id: derivationIds[index], farmId: farmId,
            sourceParcelId: source.id, targetParcelId: child.id,
            kind: ParcelDerivationKind.subdivision,
            derivedAreaM2: child.areaM2, occurredAt: occurredAt,
            actorMembershipId: actorMembershipId,
          ),
        );
      }
      await parcels.update(source.updateMetadata(
        active: false, actorMembershipId: actorMembershipId,
        occurredAt: occurredAt));
      return children;
    }, beforeCreate: (tx, _) async { scopedTransaction = tx; });
  }

  /// Explicitly restores a missing parcel-side ID on a historical linked row.
  ///
  /// Geometry, the immutable boundary history, the link, Feature and Revision
  /// must already agree. This does not create a revision or alter geometry.
  /// The shared transaction rechecks the invariant before committing.
  Future<LandParcel> reconcileLegacySpatialIdentity({
    required String farmId,
    required String landParcelId,
  }) => transaction.run<LandParcel>((parcels, links, spatial) async {
    final parcel = await parcels.getById(farmId: farmId, id: landParcelId);
    if (parcel == null || parcel.spatialFeatureId != null) {
      throw StateError(
        'Parcel is missing or does not need legacy identity repair.',
      );
    }
    final link = await links.findByLandParcelId(parcel.id);
    if (link == null) {
      throw StateError('Legacy parcel has no persisted spatial link.');
    }
    final repaired = parcel.assignSpatialFeatureId(link.spatialFeatureId);
    final diagnosis = LandParcelBoundaryConsistencyQueries(
      links: links,
      features: spatial.featureRepository,
      revisions: spatial.revisionRepository,
    );
    if (await diagnosis.check(repaired) !=
        LandParcelBoundaryConsistency.consistent) {
      throw StateError('Legacy parcel boundary needs manual reconciliation.');
    }
    await parcels.update(repaired);
    return repaired;
  });

  Future<void> create({
    required LandParcel parcel,
    required SpatialTemporalState temporalState,
    List<CropRecord> crops = const [],
  }) {
    // Sprint 8 correction: reuse parcel.spatialFeatureId when provided.
    final providedSpatialFeatureId = parcel.spatialFeatureId;
    if (providedSpatialFeatureId != null &&
        providedSpatialFeatureId.trim().isEmpty) {
      throw const FormatException(
        'Land parcel spatialFeatureId cannot be blank when provided.',
      );
    }

    final spatialLinkId = identityGenerator.newId('spatial-link');
    final spatialFeatureId = providedSpatialFeatureId ??
        identityGenerator.newId('spatial-feature');
    final spatialRevisionId = identityGenerator.newId('spatial-revision');

    return transaction.run<void>(
      (parcels, links, spatial) => createScoped(
        parcels: parcels,
        links: links,
        spatial: spatial,
        parcel: parcel,
        temporalState: temporalState,
        spatialLinkId: spatialLinkId,
        spatialFeatureId: spatialFeatureId,
        spatialRevisionId: spatialRevisionId,
      ),
      afterCreate: crops.isEmpty
          ? null
          : (surveys) async {
              for (final crop in crops) {
                await surveys.createCrop(crop);
              }
            },
    );
  }

  /// Build a new parcel and its household within the same transaction used
  /// for SpatialFeature, initial revision, link and optional crops.
  ///
  /// [prepare] may reserve business numbers and write a new Household via the
  /// transaction-scoped survey repository. A failure anywhere rolls them back.
  Future<LandParcel> createPrepared({
    required Future<LandParcel> Function(Transaction tx, LandSurveyRepository surveys)
        prepare,
    required SpatialTemporalState temporalState,
    List<CropRecord> crops = const [],
  }) async {
    final spatialLinkId = identityGenerator.newId('spatial-link');
    final spatialFeatureId = identityGenerator.newId('spatial-feature');
    final spatialRevisionId = identityGenerator.newId('spatial-revision');
    LandParcel? prepared;
    return transaction.run<LandParcel>(
      (parcels, links, spatial) async {
        final parcel = prepared!;
        await createScoped(
          parcels: parcels,
          links: links,
          spatial: spatial,
          parcel: parcel,
          temporalState: temporalState,
          spatialLinkId: spatialLinkId,
          spatialFeatureId: spatialFeatureId,
          spatialRevisionId: spatialRevisionId,
        );
        return parcel.assignSpatialFeatureId(spatialFeatureId);
      },
      beforeCreate: (tx, surveys) async {
        prepared = await prepare(tx, surveys);
        if (prepared!.spatialFeatureId != null) {
          throw const FormatException('Prepared parcel must not already have a spatial identity.');
        }
      },
      afterCreate: crops.isEmpty ? null : (surveys) async {
        for (final crop in crops) {
          await surveys.createCrop(crop);
        }
      },
    );
  }

  /// Exposes only the numbering port to application code; SQLite stays in the
  /// transaction adapter and the same transaction owns both code and parcel.
  Future<LandParcel> createPreparedWithAllocator({
    required Future<LandParcel> Function(
      ParcelNumberAllocator numbers,
      LandSurveyRepository surveys,
    ) prepare,
    required SpatialTemporalState temporalState,
    List<CropRecord> crops = const [],
  }) => createPrepared(
    temporalState: temporalState,
    crops: crops,
    prepare: (tx, surveys) =>
        prepare(SqliteScopedParcelNumberAllocator(tx), surveys),
  );

  /// Creates LandParcel and its initial Spatial projection using repositories
  /// that already belong to the caller's atomic transaction.
  Future<void> createScoped({
    required LandParcelRepository parcels,
    required LandParcelSpatialLinkRepository links,
    required SpatialPersistenceComposition spatial,
    required LandParcel parcel,
    required SpatialTemporalState temporalState,
    required String spatialLinkId,
    required String spatialFeatureId,
    required String spatialRevisionId,
  }) async {
    // Persist the stable identity with the first parcel row. A later link
    // must never leave a newly created parcel without its Spatial Core ID.
    final linkedParcel = parcel.assignSpatialFeatureId(spatialFeatureId);
    await parcels.create(linkedParcel);

    await createSpatialForParcelScoped(
      links: links,
      spatial: spatial,
      parcel: linkedParcel,
      temporalState: temporalState,
      spatialLinkId: spatialLinkId,
      spatialFeatureId: spatialFeatureId,
      spatialRevisionId: spatialRevisionId,
    );
  }

  /// Adopts an already-persisted legacy LandParcel into Spatial Core without
  /// recreating or mutating the LandParcel itself.
  Future<void> bootstrapExisting({
    required String farmId,
    required String landParcelId,
    required SpatialTemporalState temporalState,
  }) {
    return transaction.run<void>(
      (parcels, links, spatial) => bootstrapExistingScoped(
        parcels: parcels,
        links: links,
        spatial: spatial,
        farmId: farmId,
        landParcelId: landParcelId,
        temporalState: temporalState,
      ),
    );
  }

  /// Adopts an existing LandParcel using repositories that already belong to
  /// the caller's atomic transaction.
  Future<void> bootstrapExistingScoped({
    required LandParcelRepository parcels,
    required LandParcelSpatialLinkRepository links,
    required SpatialPersistenceComposition spatial,
    required String farmId,
    required String landParcelId,
    required SpatialTemporalState temporalState,
  }) async {
    final parcel = await parcels.getById(farmId: farmId, id: landParcelId);

    if (parcel == null) {
      throw StateError(
        'Land parcel $landParcelId does not exist in farm $farmId.',
      );
    }

    final existingLink = await links.findByLandParcelId(landParcelId);

    if (existingLink != null) {
      throw StateError(
        'Land parcel $landParcelId already has a persisted SpatialFeature link.',
      );
    }

    final spatialLinkId = identityGenerator.newId('spatial-link');
    final spatialFeatureId = identityGenerator.newId('spatial-feature');
    final spatialRevisionId = identityGenerator.newId('spatial-revision');

    await createSpatialForParcelScoped(
      links: links,
      spatial: spatial,
      parcel: parcel,
      temporalState: temporalState,
      spatialLinkId: spatialLinkId,
      spatialFeatureId: spatialFeatureId,
      spatialRevisionId: spatialRevisionId,
    );

    // Sprint 10 correction: establish LandParcel.spatialFeatureId
    // so the canonical identity invariant holds:
    //   LandParcel.spatialFeatureId
    //     == LandParcelSpatialLink.spatialFeatureId
    //     == SpatialFeature.id
    //
    // This runs inside the same LandParcelSpatialTransaction.run()
    // boundary, so failure here rolls back the SpatialFeature,
    // Revision 1, Link, and the LandParcel update together.
    final parcelWithSpatialIdentity =
        parcel.assignSpatialFeatureId(spatialFeatureId);
    await parcels.update(parcelWithSpatialIdentity);
  }

  /// Creates Spatial revision 1 and the stable parcel link without creating or
  /// mutating the LandParcel business record.
  ///
  /// The caller owns the surrounding transaction.
  Future<void> createSpatialForParcelScoped({
    required LandParcelSpatialLinkRepository links,
    required SpatialPersistenceComposition spatial,
    required LandParcel parcel,
    required SpatialTemporalState temporalState,
    required String spatialLinkId,
    required String spatialFeatureId,
    required String spatialRevisionId,
    String? changeReason,
  }) async {
    final projected = projection.project(
      parcel: parcel,
      spatialFeatureId: spatialFeatureId,
      spatialRevisionId: spatialRevisionId,
      spatialRevision: 1,
      temporalState: temporalState,
      effectiveFrom: parcel.updatedAt,
      changeReason: changeReason,
    );

    final link = LandParcelSpatialLink(
      id: spatialLinkId,
      landParcelId: parcel.id,
      spatialFeatureId: spatialFeatureId,
      createdAt: parcel.createdAt,
      createdBy: parcel.createdBy,
    );

    await spatial.createFeature.execute(
      feature: projected.feature,
      initialRevision: projected.revision,
    );

    await links.create(link);
  }

  /// Appends the next Spatial revision without mutating the LandParcel business
  /// record.
  ///
  /// The caller owns the surrounding transaction.
  Future<void> updateSpatialForParcelScoped({
    required LandParcelSpatialLinkRepository links,
    required SpatialPersistenceComposition spatial,
    required LandParcel parcel,
    required SpatialTemporalState temporalState,
    String? changeReason,
  }) async {
    final link = await links.findByLandParcelId(parcel.id);

    if (link == null) {
      throw StateError(
        'Land parcel ${parcel.id} has no persisted SpatialFeature link.',
      );
    }

    // Sprint 12 (D1): identity guard.
    //
    // For a spatial-enabled LandParcel entering workflow.update():
    // - persisted Link MUST exist;
    // - LandParcel.spatialFeatureId MUST be established;
    // - LandParcel.spatialFeatureId MUST match Link.spatialFeatureId.
    //
    // Any violation fails closed. Silent repair is forbidden.
    final parcelSpatialFeatureId = parcel.spatialFeatureId;

    if (parcelSpatialFeatureId == null) {
      throw StateError(
        'Spatial-enabled LandParcel ${parcel.id} has no established '
        'spatialFeatureId. Use bootstrapExisting() for legacy adoption.',
      );
    }

    if (parcelSpatialFeatureId != link.spatialFeatureId) {
      throw StateError(
        'LandParcel.spatialFeatureId ($parcelSpatialFeatureId) '
        'does not match persisted LandParcelSpatialLink.spatialFeatureId '
        '(${link.spatialFeatureId}) for parcel ${parcel.id}.',
      );
    }

    final spatialFeatureId = link.spatialFeatureId;

    final existingFeature = await spatial.featureRepository.findById(
      spatialFeatureId,
    );

    if (existingFeature == null) {
      throw StateError(
        'Linked Spatial feature $spatialFeatureId does not exist.',
      );
    }

    if (existingFeature.featureType != SpatialFeatureTypes.landParcel) {
      throw StateError(
        'Linked Spatial feature $spatialFeatureId must be a LandParcel feature, '
        'but was ${existingFeature.featureType}.',
      );
    }

    final latestRevision = await spatial.revisionRepository
        .findLatestByFeatureId(spatialFeatureId);

    if (latestRevision == null) {
      throw StateError(
        'Linked Spatial feature $spatialFeatureId has no persisted revision.',
      );
    }

    final spatialRevisionId = identityGenerator.newId('spatial-revision');

    final projected = projection.project(
      parcel: parcel,
      spatialFeatureId: spatialFeatureId,
      spatialRevisionId: spatialRevisionId,
      spatialRevision: latestRevision.revision + 1,
      temporalState: temporalState,
      effectiveFrom: parcel.updatedAt,
      changeReason: changeReason,
    );

    await spatial.updateFeature.execute(
      feature: projected.feature,
      revision: projected.revision,
    );
  }

  Future<void> update({
    required LandParcel parcel,
    required SpatialTemporalState temporalState,
  }) {
    return transaction.run<void>(
      (parcels, links, spatial) => updateScoped(
        parcels: parcels,
        links: links,
        spatial: spatial,
        parcel: parcel,
        temporalState: temporalState,
      ),
    );
  }

  /// Updates LandParcel and its Spatial projection using repositories that
  /// already belong to the caller's atomic transaction.
  Future<void> updateScoped({
    required LandParcelRepository parcels,
    required LandParcelSpatialLinkRepository links,
    required SpatialPersistenceComposition spatial,
    required LandParcel parcel,
    required SpatialTemporalState temporalState,
  }) async {
    await parcels.update(parcel);

    await updateSpatialForParcelScoped(
      links: links,
      spatial: spatial,
      parcel: parcel,
      temporalState: temporalState,
    );
  }
}
