import 'dart:convert';

import '../../../core/identity/domain/production_parcel_reference_code.dart';
import '../domain/geometry/field_plot_placement.dart';
import '../data/local/sqlite_land_parcel_repository.dart';
import '../data/local/sqlite_land_parcel_spatial_link_repository.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/identity/domain/parcel_number_allocator.dart';
import '../../../core/identity/data/sqlite_production_parcel_number_allocator.dart';
import '../../../core/identity/data/sqlite_scoped_parcel_number_allocator.dart';

import 'package:agrico_deepseek/core/spatial/domain/entities/spatial_feature.dart';
import 'package:agrico_deepseek/core/spatial/domain/identity/spatial_identity_generator.dart';
import '../../../core/spatial/domain/entities/spatial_temporal.dart';
import '../data/adapters/land_parcel_spatial_projection.dart';
import '../data/adapters/land_parcel_spatial_transaction.dart';
import '../data/local/sqlite_parcel_land_history_repository.dart';
import '../domain/entities/land_parcel.dart';
import '../domain/entities/parcel_land_history.dart';
import '../domain/geometry/parcel_subdivision_plan.dart';
import '../domain/geometry/wgs84_geometry.dart';
import '../domain/geometry/wgs84_topology.dart';
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
/// Every public entry point runs inside a single shared transaction so the
/// parcel, its immutable boundary history, the spatial link, the
/// SpatialFeature and its first revision either commit together or roll back
/// together.
class LandParcelSpatialSyncWorkflow {
  const LandParcelSpatialSyncWorkflow({
    required this.transaction,
    required this.projection,
    required this.identityGenerator,
  });

  final LandParcelSpatialTransaction transaction;
  final LandParcelSpatialProjection projection;
  final SpatialIdentityGenerator identityGenerator;

  /// Subdivide [sourceParcelId] into fragments along [cuts].
  ///
  /// All fragments share the same transaction. When [independentSketches] is
  /// true the fragments are produced as standalone field plots, otherwise the
  /// source land block is deactivated once the fragments have been written.
  Future<List<LandParcel>> subdividePlan({
    required String farmId,
    required String sourceParcelId,
    required String villageId,
    required int expectedBoundaryVersion,
    required List<ParcelSubdivisionCut> cuts,
    required List<String> names,
    required String actorMembershipId,
    required DateTime occurredAt,
    bool independentSketches = false,
    List<ParcelSketchDetails> details = const [],
  }) async {
    if (cuts.isEmpty ||
        cuts.length > 99 ||
        names.length != cuts.length + (independentSketches ? 0 : 1) ||
        names.any((name) => name.trim().isEmpty) ||
        villageId.trim().isEmpty ||
        (details.isNotEmpty && details.length != names.length)) {
      throw const FormatException(
        'Every final fragment needs a name and catalogued village.',
      );
    }
    final entries = details.isEmpty
        ? List.filled(names.length, const ParcelSketchDetails())
        : details;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final parentIndex = entry.parentSketchIndex;
      if (parentIndex != null &&
          (parentIndex < 0 ||
              parentIndex >= i ||
              entries[parentIndex].layer != ParcelLayer.landBlock)) {
        throw const FormatException(
          'A field plot must refer to a previously drawn land block.',
        );
      }
      if (entry.cropType?.trim().isNotEmpty == true &&
          (entry.cropQuantity == null ||
              !entry.cropQuantity!.isFinite ||
              entry.cropQuantity! <= 0 ||
              entry.cropUnit?.trim().isEmpty != false)) {
        throw const FormatException(
          'Crop requires a positive quantity and unit.',
        );
      }
    }
    final childIds = List.generate(
      names.length,
      (_) => identityGenerator.newId('land-parcel'),
    );
    final linkIds = List.generate(
      names.length,
      (_) => identityGenerator.newId('spatial-link'),
    );
    final featureIds = List.generate(
      names.length,
      (_) => identityGenerator.newId('spatial-feature'),
    );
    final revisionIds = List.generate(
      names.length,
      (_) => identityGenerator.newId('spatial-revision'),
    );
    final derivationIds = List.generate(
      names.length,
      (_) => identityGenerator.newId('derivation'),
    );
    Transaction? scopedTransaction;
    final createdChildren = <LandParcel>[];
    return transaction.run<List<LandParcel>>(
      (parcels, links, spatial) async {
        final tx = scopedTransaction!;
        final source = await parcels.getById(
          farmId: farmId,
          id: sourceParcelId,
        );
        if (source == null ||
            !source.active ||
            source.boundaryVersion != expectedBoundaryVersion ||
            source.countryCode == null ||
            source.provinceCode == null ||
            source.districtCode == null ||
            source.villageCode == null) {
          throw StateError(
            'Source parcel changed or has no catalogued location.',
          );
        }
        if (independentSketches && source.layer != ParcelLayer.landBlock) {
          throw StateError('Field plots must belong to a land block.');
        }
        if (source.spatialFeatureId == null ||
            await LandParcelBoundaryConsistencyQueries(
                  links: links,
                  features: spatial.featureRepository,
                  revisions: spatial.revisionRepository,
                ).check(source) !=
                LandParcelBoundaryConsistency.consistent) {
          throw StateError('Source parcel boundary needs reconciliation.');
        }
        final existingSplit = await tx.query(
          SqliteParcelLandHistoryRepository.derivationsTable,
          columns: ['id'],
          where:
              'farm_id = ? AND source_parcel_id = ? '
              'AND kind = ?',
          whereArgs: [farmId, source.id, ParcelDerivationKind.subdivision.name],
          limit: 1,
        );
        if (!independentSketches && existingSplit.isNotEmpty) {
          throw StateError('Source parcel has already been subdivided.');
        }
        final location = await tx.rawQuery(
          '''
        SELECT v.id FROM agrico_administrative_units v
        JOIN agrico_administrative_units d ON d.id = v.parent_id
        JOIN agrico_administrative_units p ON p.id = d.parent_id
        JOIN agrico_administrative_units c ON c.id = p.parent_id
        WHERE v.id = ? AND v.level = 'village' AND v.active = 1
          AND d.active = 1 AND p.active = 1 AND c.active = 1
          AND v.code = ? AND d.code = ? AND p.code = ? AND c.code = ?
      ''',
          [
            villageId,
            source.villageCode,
            source.districtCode,
            source.provinceCode,
            source.countryCode,
          ],
        );
        if (location.length != 1) {
          throw const FormatException(
            'Parcel village does not match the catalog.',
          );
        }
        final plan = const ParcelSubdivisionPlan();
        final boundaries = independentSketches
            ? plan.sketches(cuts)
            : plan.apply(source.boundary, cuts);

        // P02A: block-on-block guard. A new land block must not overlap the
        // interior of any other active land block in the same project.
        // NULL project is transitional and is still compared ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â it is not
        // treated as a real project.
        await _guardBlockOverlaps(
          tx: tx,
          farmId: farmId,
          sourceId: source.id,
          sourceProjectId: source.projectId,
          sourceBoundary: source.boundary,
          sourceStaysActive: independentSketches,
          boundaries: boundaries,
          entries: entries,
          independentSketches: independentSketches,
        );

        final numbers = SqliteScopedParcelNumberAllocator(tx);
        final children = <LandParcel>[];
        for (var index = 0; index < boundaries.length; index++) {
          final entry = entries[index];
          final parentId = entry.parentSketchIndex == null
              ? source.id
              : childIds[entry.parentSketchIndex!];
          final child = await numbers.saveLocationParcel(
            farmId: farmId,
            villageId: villageId,
            countryCode: source.countryCode!,
            provinceCode: source.provinceCode!,
            districtCode: source.districtCode!,
            villageCode: source.villageCode!,
            save: (code) async => LandParcel.create(
              id: childIds[index],
              farmId: farmId,
              parcelCode: code,
              name: names[index].trim(),
              boundary: boundaries[index],
              boundarySource: BoundarySource.manual,
              verificationStatus: BoundaryVerificationStatus.draft,
              actorMembershipId: actorMembershipId,
              occurredAt: occurredAt,
              // P02A: typed fields. Project inherits from the source.
              projectId: source.projectId,
              kind: independentSketches ? entry.layer : ParcelLayer.landBlock,
              parentBlockId:
                  independentSketches && entry.layer == ParcelLayer.fieldPlot
                  ? parentId
                  : null,
              countryCode: source.countryCode,
              provinceCode: source.provinceCode,
              districtCode: source.districtCode,
              villageCode: source.villageCode,
            ),
          );
          await createScoped(
            parcels: parcels,
            links: links,
            spatial: spatial,
            parcel: child,
            temporalState: SpatialTemporalState.underConstruction,
            spatialLinkId: linkIds[index],
            spatialFeatureId: featureIds[index],
            spatialRevisionId: revisionIds[index],
          );
          children.add(child.assignSpatialFeatureId(featureIds[index]));
          createdChildren.add(children.last);
          await SqliteParcelLandHistoryRepository.linkScoped(
            tx,
            ParcelDerivation(
              id: derivationIds[index],
              farmId: farmId,
              sourceParcelId: source.id,
              targetParcelId: child.id,
              kind: ParcelDerivationKind.subdivision,
              derivedAreaM2: child.areaM2,
              occurredAt: occurredAt,
              actorMembershipId: actorMembershipId,
            ),
            allowOutsideSource: independentSketches,
          );
        }
        if (!independentSketches) {
          await parcels.update(
            source.updateMetadata(
              active: false,
              actorMembershipId: actorMembershipId,
              occurredAt: occurredAt,
            ),
          );
        }
        return children;
      },
      beforeCreate: (tx, _) async {
        scopedTransaction = tx;
      },
      afterCreate: (surveys) async {
        if (!independentSketches) return;
        for (var i = 0; i < createdChildren.length; i++) {
          final entry = entries[i];
          final child = createdChildren[i];
          // P02A: land-use profiles and crops belong to field plots only.
          // A land block created by subdivision never carries them, even
          // when the input sketch authorises such metadata.
          if (child.layer != ParcelLayer.fieldPlot) continue;
          await surveys.saveLandUseProfile(
            LandUseProfile(
              parcelId: child.id,
              landUseType: entry.landUseType,
              currentCondition: entry.landCondition,
              clearingStatus: entry.clearingStatus,
              readinessStatus: entry.readinessStatus,
              notes: entry.notes?.trim().isEmpty == true
                  ? null
                  : entry.notes?.trim(),
              updatedAt: occurredAt,
              updatedBy: actorMembershipId,
            ),
          );
          if (entry.cropType?.trim().isNotEmpty == true) {
            await surveys.createCrop(
              CropRecord(
                id: identityGenerator.newId('crop'),
                parcelId: child.id,
                cropType: entry.cropType!.trim(),
                quantity: entry.cropQuantity!,
                unit: entry.cropUnit!.trim(),
                condition: CropCondition.growing,
                growthStage: entry.cropGrowthStage,
                active: true,
                createdAt: occurredAt,
                createdBy: actorMembershipId,
                updatedAt: occurredAt,
                updatedBy: actorMembershipId,
              ),
            );
          }
        }
      },
    );
  }

  /// P02A block-on-block guard. Rejects any new land block whose interior
  /// overlaps another active land block within the same project scope.
  ///
  /// Scope rule (transitional, per approved contract):
  /// - NULL vs NULL: check (both are undetermined).
  /// - NULL vs X: check (undetermined cannot skip a defined project).
  /// - X vs X: check (same project).
  /// - X vs Y (different): skip (different projects do not overlap for
  ///   agricultural management purposes).
  ///
  /// Shared edges or vertices are allowed.
  Future<void> _guardBlockOverlaps({
    required Transaction tx,
    required String farmId,
    required String sourceId,
    required String? sourceProjectId,
    required Wgs84Polygon sourceBoundary,
    required bool sourceStaysActive,
    required List<Wgs84Polygon> boundaries,
    required List<ParcelSketchDetails> entries,
    required bool independentSketches,
  }) async {
    final rows = await tx.query(
      SqliteLandParcelRepository.parcelTable,
      columns: ['id', 'payload_json', 'kind', 'parent_block_id', 'project_id'],
      where: 'farm_id = ? AND active = 1',
      whereArgs: [farmId],
    );
    final existingBlocks = <Wgs84Polygon>[];
    for (final row in rows) {
      if ((row['kind'] as String?) != 'landBlock') continue;
      if ((row['parent_block_id'] as String?) != null) continue;
      final id = row['id'] as String;
      if (id == sourceId) continue;
      final rowProject = row['project_id'] as String?;
      final inSameScope = _sameProjectScope(sourceProjectId, rowProject);
      if (!inSameScope) continue;
      final decoded = jsonDecode(row['payload_json'] as String) as Map;
      existingBlocks.add(_decodeBoundary(decoded['boundary']));
    }
    final activeBlocks = <Wgs84Polygon>[
      if (sourceStaysActive) sourceBoundary,
      ...existingBlocks,
    ];

    const topology = Wgs84Topology();
    final accepted = <Wgs84Polygon>[];
    for (var i = 0; i < boundaries.length; i++) {
      final candidateKind = independentSketches
          ? entries[i].layer
          : ParcelLayer.landBlock;
      if (candidateKind != ParcelLayer.landBlock) continue;
      for (final other in activeBlocks) {
        if (topology.interiorsOverlap(boundaries[i], other)) {
          throw StateError(
            'New land block overlaps an existing active land block.',
          );
        }
      }
      for (final other in accepted) {
        if (topology.interiorsOverlap(boundaries[i], other)) {
          throw StateError('New land blocks in the same batch overlap.');
        }
      }
      accepted.add(boundaries[i]);
    }
  }

  /// Scope rule for the block-on-block guard.
  ///
  /// - Different non-null projects are the only scope that skips the check.
  /// - Any combination that involves NULL is checked, because NULL means
  ///   "undetermined" during transition and is not a real project.
  bool _sameProjectScope(String? a, String? b) {
    if (a != null && b != null && a != b) return false;
    return true;
  }

  /// Decodes a persisted boundary payload into a WGS84 polygon.
  Wgs84Polygon _decodeBoundary(Object? raw) {
    if (raw is List) {
      final vertices = raw.map((point) {
        final item = point as Map;
        return Wgs84Vertex(
          latitude: (item['latitude'] as num).toDouble(),
          longitude: (item['longitude'] as num).toDouble(),
          altitudeM: (item['altitudeM'] as num?)?.toDouble(),
        );
      });
      return Wgs84Polygon.fromVertices(vertices);
    }
    if (raw is Map) {
      final outer = raw['outerRing'] as List;
      final inner = (raw['innerRings'] as List?) ?? const [];
      final vertices = outer.map((point) {
        final item = point as Map;
        return Wgs84Vertex(
          latitude: (item['latitude'] as num).toDouble(),
          longitude: (item['longitude'] as num).toDouble(),
          altitudeM: (item['altitudeM'] as num?)?.toDouble(),
        );
      });
      final holes = inner.map((ring) {
        return (ring as List).map((point) {
          final item = point as Map;
          return Wgs84Vertex(
            latitude: (item['latitude'] as num).toDouble(),
            longitude: (item['longitude'] as num).toDouble(),
            altitudeM: (item['altitudeM'] as num?)?.toDouble(),
          );
        });
      });
      return Wgs84Polygon.fromVertices(vertices, holes: holes);
    }
    throw const FormatException('Unsupported boundary encoding.');
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
    final spatialFeatureId =
        providedSpatialFeatureId ?? identityGenerator.newId('spatial-feature');
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
    required Future<LandParcel> Function(
      Transaction tx,
      LandSurveyRepository surveys,
    )
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
          throw const FormatException(
            'Prepared parcel must not already have a spatial identity.',
          );
        }
      },
      afterCreate: crops.isEmpty
          ? null
          : (surveys) async {
              for (final crop in crops) {
                await surveys.createCrop(crop);
              }
            },
    );
  }

  /// Saves a production block with a project-scoped code in the same
  /// transaction as its spatial identity, revision and link.
  /// Administrative location and ownership do not participate in numbering.
  Future<LandParcel> createProductionLandBlock({
    required LandParcel draft,
    required String projectCode,
    List<CropRecord> crops = const [],
    required SpatialTemporalState temporalState,
  }) {
    if (draft.layer != ParcelLayer.landBlock ||
        draft.parentLandBlockId != null ||
        draft.spatialFeatureId != null) {
      throw const FormatException(
        'A new production block cannot have a parent or spatial identity.',
      );
    }
    // P02A: a production land block must never carry crops. This rejects
    // callers that reach the workflow directly, bypassing the application
    // service layer.
    if (crops.isNotEmpty) {
      throw const FormatException(
        'A production land block cannot carry crops.',
      );
    }
    // P02A: project identity is a first-class field. The caller must supply
    // the project id from the project catalog; the code prefix is used
    // only for numbering and is not treated as a project identifier.
    if (draft.projectId == null || draft.projectId!.trim().isEmpty) {
      throw const FormatException(
        'A production land block requires a project id on the draft.',
      );
    }
    return createPrepared(
      crops: crops,
      temporalState: temporalState,
      prepare: (tx, surveys) async {
        // P02A: block-on-block guard for production block creation.
        // Runs inside the transaction, re-reads the current persisted state
        // and enforces the same project / NULL rule as subdivision.
        await _guardProductionBlockOverlaps(
          tx: tx,
          farmId: draft.farmId,
          candidateProjectId: draft.projectId,
          candidateBoundary: draft.boundary,
        );
        return SqliteProductionParcelNumberAllocator(tx).saveLandBlock(
          farmId: draft.farmId,
          projectCode: projectCode,
          save: (code) async => draft.updateMetadata(
            parcelCode: code.toString(),
            actorMembershipId: draft.createdBy,
            occurredAt: draft.createdAt,
          ),
        );
      },
    );
  }

  /// P02A production-block guard. Rejects a new production land block whose
  /// interior overlaps any active land block within the same project scope.
  ///
  /// Scope rule matches subdivision:
  /// - X vs X: check.
  /// - X vs Y (different): skip.
  /// - NULL vs anything: check (NULL is transitional, not a real project).
  Future<void> _guardProductionBlockOverlaps({
    required Transaction tx,
    required String farmId,
    required String? candidateProjectId,
    required Wgs84Polygon candidateBoundary,
  }) async {
    final rows = await tx.query(
      SqliteLandParcelRepository.parcelTable,
      columns: ['id', 'payload_json', 'kind', 'parent_block_id', 'project_id'],
      where: 'farm_id = ? AND active = 1',
      whereArgs: [farmId],
    );
    const topology = Wgs84Topology();
    for (final row in rows) {
      if ((row['kind'] as String?) != 'landBlock') continue;
      if ((row['parent_block_id'] as String?) != null) continue;
      final rowProject = row['project_id'] as String?;
      if (!_sameProjectScope(candidateProjectId, rowProject)) continue;
      final decoded = jsonDecode(row['payload_json'] as String) as Map;
      final other = _decodeBoundary(decoded['boundary']);
      if (topology.interiorsOverlap(candidateBoundary, other)) {
        throw StateError(
          'New production land block overlaps an existing active land block.',
        );
      }
    }
  }

  /// Creates one field plot without requiring complete coverage of its block.
  /// The parent, existing plots, code and spatial writes share one transaction.
  Future<LandParcel> createProductionStandaloneFieldPlot({
    required LandParcel draft,
    required String projectCode,
    required SpatialTemporalState temporalState,
  }) {
    if (draft.kind != ParcelLayer.fieldPlot ||
        draft.parentBlockId != null ||
        draft.projectId == null ||
        draft.projectId!.trim().isEmpty ||
        draft.spatialFeatureId != null ||
        !draft.active ||
        draft.boundaryVersion != 1) {
      throw const FormatException(
        'Standalone production field plot draft is invalid.',
      );
    }

    return createPrepared(
      temporalState: temporalState,
      prepare: (tx, surveys) {
        return SqliteProductionParcelNumberAllocator(
          tx,
        ).saveStandaloneFieldPlot(
          farmId: draft.farmId,
          projectCode: projectCode,
          save: (code) async => LandParcel.create(
            id: draft.id,
            farmId: draft.farmId,
            parcelCode: code.toString(),
            name: draft.name,
            boundary: draft.boundary,
            boundarySource: draft.boundarySource,
            verificationStatus: draft.verificationStatus,
            actorMembershipId: draft.createdBy,
            occurredAt: draft.createdAt,
            ownerHouseholdId: draft.ownerHouseholdId,
            ownerDisplayName: draft.ownerDisplayName,
            ownerContact: draft.ownerContact,
            active: draft.active,
            horizontalAccuracyM: draft.horizontalAccuracyM,
            boundaryConfidence: draft.boundaryConfidence,
            countryCode: draft.countryCode,
            provinceCode: draft.provinceCode,
            districtCode: draft.districtCode,
            villageCode: draft.villageCode,
            projectId: draft.projectId,
            kind: ParcelLayer.fieldPlot,
            parentBlockId: null,
            legacyMetadata: draft.legacyMetadata,
          ),
        );
      },
    );
  }

  Future<LandParcel> createProductionFieldPlot({
    required LandParcel draft,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
  }) => createPrepared(
    temporalState: temporalState,
    prepare: (tx, surveys) => _prepareProductionFieldPlot(
      tx: tx,
      draft: draft,
      parentLandBlockId: parentLandBlockId,
      expectedParentBoundaryVersion: expectedParentBoundaryVersion,
    ),
  );

  Future<LandParcel> _prepareProductionFieldPlot({
    required Transaction tx,
    required LandParcel draft,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
  }) async {
    if (parentLandBlockId.trim().isEmpty ||
        draft.id == parentLandBlockId ||
        !draft.active ||
        draft.spatialFeatureId != null ||
        draft.boundaryVersion != 1) {
      throw const FormatException(
        'A field plot requires a new draft and distinct parent.',
      );
    }
    final parcels = SqliteLandParcelRepository(tx);
    final parent = await parcels.getById(
      farmId: draft.farmId,
      id: parentLandBlockId,
    );
    if (parent == null ||
        !parent.active ||
        parent.layer != ParcelLayer.landBlock ||
        parent.parentLandBlockId != null ||
        parent.boundaryVersion != expectedParentBoundaryVersion) {
      throw StateError('Parent land block is missing, inactive or changed.');
    }
    final spatial = SpatialPersistenceComposition(tx);
    if (parent.spatialFeatureId == null ||
        await LandParcelBoundaryConsistencyQueries(
              links: SqliteLandParcelSpatialLinkRepository(tx),
              features: spatial.featureRepository,
              revisions: spatial.revisionRepository,
            ).check(parent) !=
            LandParcelBoundaryConsistency.consistent) {
      throw StateError('Parent land block boundary needs reconciliation.');
    }
    final match = RegExp(r'^(.+)-L([0-9]+)$').firstMatch(parent.parcelCode);
    if (match == null) {
      throw const FormatException(
        'Parent requires a production land block code.',
      );
    }
    final parentCode = ProductionParcelReferenceCode.landBlock(
      projectCode: match.group(1)!,
      landBlockNumber: int.parse(match.group(2)!),
    );
    if (parentCode.toString() != parent.parcelCode) {
      throw const FormatException('Parent production code is not canonical.');
    }
    final siblings = await parcels.listByFarm(draft.farmId);
    const FieldPlotPlacement().validate(
      block: parent.boundary,
      plot: draft.boundary,
      existingPlots: siblings
          .where(
            (item) =>
                item.active &&
                item.layer == ParcelLayer.fieldPlot &&
                item.parentLandBlockId == parent.id,
          )
          .map((item) => item.boundary),
    );
    return SqliteProductionParcelNumberAllocator(tx).saveFieldPlot(
      farmId: draft.farmId,
      parent: parentCode,
      save: (code) async => LandParcel.create(
        id: draft.id,
        farmId: draft.farmId,
        parcelCode: code.toString(),
        name: draft.name,
        boundary: draft.boundary,
        boundarySource: draft.boundarySource,
        verificationStatus: draft.verificationStatus,
        actorMembershipId: draft.createdBy,
        occurredAt: draft.createdAt,
        ownerHouseholdId: draft.ownerHouseholdId,
        ownerDisplayName: draft.ownerDisplayName,
        ownerContact: draft.ownerContact,
        horizontalAccuracyM: draft.horizontalAccuracyM,
        boundaryConfidence: draft.boundaryConfidence,
        note: draft.boundaryHistory.first.note,
        countryCode: draft.countryCode,
        provinceCode: draft.provinceCode,
        districtCode: draft.districtCode,
        villageCode: draft.villageCode,
        // P02A: typed fields. The plot inherits the parent's project.
        projectId: parent.projectId,
        kind: ParcelLayer.fieldPlot,
        parentBlockId: parent.id,
        legacyMetadata: draft.legacyMetadata,
      ),
    );
  }

  Future<List<LandParcel>> createProductionFieldPlots({
    required List<LandParcel> drafts,
    required String parentLandBlockId,
    required int expectedParentBoundaryVersion,
    required SpatialTemporalState temporalState,
    required List<ParcelSketchDetails> details,
  }) {
    if (drafts.isEmpty ||
        details.length != drafts.length ||
        drafts.map((draft) => draft.id).toSet().length != drafts.length ||
        drafts.map((draft) => draft.farmId).toSet().length != 1) {
      throw const FormatException('Invalid production plot batch.');
    }
    late Transaction tx;
    final created = <LandParcel>[];
    return transaction.run<List<LandParcel>>(
      (parcels, links, spatial) async {
        for (final draft in drafts) {
          final prepared = await _prepareProductionFieldPlot(
            tx: tx,
            draft: draft,
            parentLandBlockId: parentLandBlockId,
            expectedParentBoundaryVersion: expectedParentBoundaryVersion,
          );
          final featureId = identityGenerator.newId('spatial-feature');
          await createScoped(
            parcels: parcels,
            links: links,
            spatial: spatial,
            parcel: prepared,
            temporalState: temporalState,
            spatialLinkId: identityGenerator.newId('spatial-link'),
            spatialFeatureId: featureId,
            spatialRevisionId: identityGenerator.newId('spatial-revision'),
          );
          created.add(prepared.assignSpatialFeatureId(featureId));
        }
        return created;
      },
      beforeCreate: (scoped, surveys) async {
        tx = scoped;
      },
      afterCreate: (surveys) async {
        for (var i = 0; i < created.length; i++) {
          final child = created[i];
          final entry = details[i];
          // P02A: profiles and crops belong to field plots only.
          if (child.layer != ParcelLayer.fieldPlot) continue;
          await surveys.saveLandUseProfile(
            LandUseProfile(
              parcelId: child.id,
              landUseType: entry.landUseType,
              currentCondition: entry.landCondition,
              clearingStatus: entry.clearingStatus,
              readinessStatus: entry.readinessStatus,
              notes: entry.notes?.trim().isEmpty == true
                  ? null
                  : entry.notes?.trim(),
              updatedAt: child.updatedAt,
              updatedBy: child.updatedBy,
            ),
          );
          if (entry.cropType?.trim().isNotEmpty == true) {
            await surveys.createCrop(
              CropRecord(
                id: identityGenerator.newId('crop'),
                parcelId: child.id,
                cropType: entry.cropType!.trim(),
                quantity: entry.cropQuantity!,
                unit: entry.cropUnit!.trim(),
                condition: CropCondition.growing,
                growthStage: entry.cropGrowthStage,
                active: true,
                createdAt: child.createdAt,
                createdBy: child.createdBy,
                updatedAt: child.updatedAt,
                updatedBy: child.updatedBy,
              ),
            );
          }
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
    )
    prepare,
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
    final parcelWithSpatialIdentity = parcel.assignSpatialFeatureId(
      spatialFeatureId,
    );
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
