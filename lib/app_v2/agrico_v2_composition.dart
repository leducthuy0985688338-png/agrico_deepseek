import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization/app_localizations.dart';
import '../core/permissions/authorization.dart';
import '../core/spatial/data/identity/default_spatial_identity_generator.dart';
import '../core/spatial/data/spatial_persistence_composition.dart';
import '../features/farm/application/land_parcel_application_service.dart';
import '../features/farm/application/land_parcel_spatial_sync_workflow.dart';
import '../features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import '../features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import '../features/farm/application/land_parcel_use_cases.dart';
import '../features/farm/data/legacy/land_parcel_legacy_migration.dart';
import '../features/farm/data/legacy/legacy_field_adapter.dart';
import '../features/farm/data/local/sqlite_land_parcel_repository.dart';
import '../features/farm/data/local/sqlite_land_survey_repository.dart';
import '../features/farm/domain/entities/land_parcel.dart';
import '../features/farm/domain/geometry/wgs84_geometry.dart';
import '../features/farm/presentation/controllers/land_parcel_controller.dart';
import '../features/farm/presentation/platform/land_parcel_platform_io.dart';
import '../features/farm/presentation/screens/land_parcel_detail_screen.dart';
import '../features/farm/presentation/screens/land_parcel_form_screen.dart';
import '../features/farm/presentation/screens/land_parcel_list_screen.dart';
import '../features/farm/presentation/widgets/boundary_workflow_widgets.dart';
import '../models/field_model.dart';
import '../providers/field_provider.dart';
import '../providers/production_season_provider.dart';
import '../providers/task_provider.dart';
import '../screens/ai_chat_screen.dart';
import '../screens/employee_list_screen.dart';
import '../screens/field_gps_measure_screen.dart';
import '../screens/finance_screen.dart';
import '../screens/fuel_screen.dart';
import '../screens/machine_list_screen.dart';
import '../screens/report_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/task_screen.dart';
import '../screens/warehouse_screen.dart';
import '../services/field_database.dart';
import 'agrico_app_shell.dart';

class AgricoV2Root extends StatefulWidget {
  const AgricoV2Root({super.key, required this.userId});
  final String userId;
  @override
  State<AgricoV2Root> createState() => _AgricoV2RootState();
}

class _AgricoV2RootState extends State<AgricoV2Root> {
  late final Future<_V2Dependencies> dependencies = _bootstrap();

  Future<_V2Dependencies> _bootstrap() async {
    final sharedDatabase = FieldDatabase();
    final database = await sharedDatabase.database;
    final spatial = SpatialPersistenceComposition(database);
    await SqliteLandSurveyRepository.createSchema(database);
    final parcels = SqliteLandParcelRepository(database);
    final legacyFields = await sharedDatabase.getAll();
    await const LandParcelLegacyMigration().migrate(
      legacyRecords: legacyFields,
      policy: LegacyFieldMigrationPolicy(
        farmId: 'local-farm',
        actorMembershipId: 'local-membership',
        occurredAt: DateTime.now().toUtc(),
        parcelCode: (field) => field.id,
        isActive: (_) => true,
        boundarySource: (field) => switch (field.measurementMethod) {
          'gps' => BoundarySource.gps,
          'manual' => BoundarySource.manual,
          _ => BoundarySource.imported,
        },
        verificationStatus: (_) => BoundaryVerificationStatus.draft,
      ),
      repository: parcels,
    );
    final subject = AuthorizationSubject(
      userId: widget.userId.isEmpty ? 'local-user' : widget.userId,
      membershipId: 'local-membership',
      farmId: 'local-farm',
      permissionCodes: PermissionCodes.values,
      dataScopes: const {DataScope.allFarm},
    );
    final spatialSyncWorkflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: DefaultSpatialIdentityGenerator(),
    );

    final application = LandParcelApplicationService(
      repository: parcels,
      spatialWorkflow: spatialSyncWorkflow,
    );
    const platform = MobileLandParcelPlatformGateway();
    return _V2Dependencies(
      subject: subject,
      spatial: spatial,
      controller: LandParcelController(
        subject: subject,
        parcels: parcels,
        surveys: SqliteLandSurveyRepository(database),
        createLandParcel: CreateLandParcel(application),
        updateMetadata: UpdateLandParcelMetadata(application),
        completeGpsMeasurement: CompleteGpsMeasurement(application),
        verifyBoundary: VerifyBoundary(application),
        importPreview: ImportKmlKmzPreview(application),
        applyImportedBoundary: ApplyImportedBoundary(application),
        exportKmlKmz: ExportKmlKmz(application),
        fileOpener: platform,
        googleEarthOpener: platform,
      ),
      platform: platform,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_V2Dependencies>(
    future: dependencies,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _StartupError(error: snapshot.error!);
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final deps = snapshot.data!;
      void push(Widget page) =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      late final VoidCallback openParcels;
      Widget detail(String id) => LandParcelDetailScreen(
        controller: deps.controller,
        parcelId: id,
        onGpsRequested: () => _measureGps(context, deps, id),
        onImportRequested: () => _import(context, deps, id),
        onEditRequested: () => _editParcel(context, deps, id),
      );
      openParcels = () => push(
        LandParcelListScreen(
          controller: deps.controller,
          onCreate: () => _createParcel(context, deps),
          detailBuilder: (_, id) => detail(id),
        ),
      );
      final legacy = <String, VoidCallback>{
        'machines': () => push(const MachineListScreen()),
        'employees': () => push(const EmployeeListScreen()),
        'finance': () => push(const FinanceScreen()),
        'warehouse': () => push(const WarehouseScreen()),
        'fuel': () => push(const FuelScreen()),
        'tasks': () => push(const TaskScreen()),
        'ai': () => push(const AiChatScreen()),
        'reports': () => push(const ReportScreen()),
        'settings': () => push(const SettingsPage()),
      };
      return AgricoAppShell(
        subject: deps.subject,
        landParcelController: deps.controller,
        openLandParcels: openParcels,
        openCreateParcel: () => _createParcel(context, deps),
        legacyRoutes: legacy,
        parcelCount: context.watch<FieldProvider>().isLoading
            ? null
            : context.watch<FieldProvider>().fields.length,
        seasonCount: context.watch<ProductionSeasonProvider>().isLoading
            ? null
            : context.watch<ProductionSeasonProvider>().allSeasons.length,
        taskCount: context.watch<TaskProvider>().tasks.length,
      );
    },
  );

  Future<void> _measureGps(
    BuildContext context,
    _V2Dependencies deps,
    String parcelId,
  ) async {
    final measured = await Navigator.of(context).push<FieldModel>(
      MaterialPageRoute(builder: (_) => const FieldGpsMeasureScreen()),
    );
    if (!context.mounted || measured == null) return;
    final parcel = await deps.controller.parcels.getById(
      farmId: deps.subject.farmId,
      id: parcelId,
    );
    if (!context.mounted || parcel == null) return;
    final vertices = measured.polygon
        .map(
          (point) =>
              Wgs84Vertex(latitude: point.latitude, longitude: point.longitude),
        )
        .toList();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GpsBoundaryPreview(
                controller: deps.controller,
                parcel: parcel,
                completedVertices: vertices,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _import(
    BuildContext context,
    _V2Dependencies deps,
    String parcelId,
  ) async {
    try {
      final selected = await deps.platform.pickKmlOrKmz();
      if (!context.mounted || selected == null) return;
      final result = selected.isKmz
          ? deps.controller.previewKmz(selected.bytes)
          : deps.controller.previewKml(utf8.decode(selected.bytes));
      final parcel = await deps.controller.parcels.getById(
        farmId: deps.subject.farmId,
        id: parcelId,
      );
      if (!context.mounted ||
          !result.isSuccess ||
          result.value == null ||
          parcel == null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(),
            body: KmlImportPreviewView(
              controller: deps.controller,
              parcel: parcel,
              preview: result.value!.previews.first,
            ),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.text('landParcel.import.failed')),
          ),
        );
      }
    }
  }

  void _editParcel(
    BuildContext context,
    _V2Dependencies deps,
    String parcelId,
  ) {
    final data = deps.controller.detail;
    if (data == null || data.parcel.id != parcelId) return;

    final parcel = data.parcel;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (editContext) => LandParcelFormScreen(
          parcel: parcel,
          household: data.household,
          crops: data.crops,
          landUse: data.landUse,
          surveys: data.surveys,
          attachments: data.attachments,
          onSubmit: (value) async {
            final result = await deps.controller.update(
              parcelId: parcel.id,
              parcelCode: value.parcelCode,
              name: value.name,
              ownerHouseholdId: parcel.ownerHouseholdId,
              ownerDisplayName: value.ownerName.isEmpty
                  ? null
                  : value.ownerName,
              active: value.active,
            );

            if (!editContext.mounted) return;

            if (!result.isSuccess) {
              ScaffoldMessenger.of(editContext).showSnackBar(
                SnackBar(
                  content: Text(editContext.l10n.text(result.messageKey)),
                ),
              );
              return;
            }

            Navigator.of(editContext).pop();
          },
        ),
      ),
    );
  }

  void _createParcel(
    BuildContext context,
    _V2Dependencies deps,
  ) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LandParcelFormScreen(
        onGpsRequested: () => _measureGpsForCreate(context),
        onImportRequested: () => _importForCreate(context, deps),
        onSubmit: (value) async {
          final draft = value.boundaryDraft;
          if (draft == null) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.text('parcel.boundaryRequired')),
                ),
              );
            }
            return;
          }

          final id = 'parcel-${DateTime.now().toUtc().microsecondsSinceEpoch}';
          final result = await deps.controller.create(
            id: id,
            parcelCode: value.parcelCode,
            name: value.name,
            vertices: draft.boundary.vertices.toList(),
            source: draft.source,
            ownerDisplayName: value.ownerName.isEmpty ? null : value.ownerName,
            legacyMetadata: {
              'active': value.active,
              'country': value.country,
              'province': value.province,
              'district': value.district,
              'village': value.village,
              'householdCode': value.householdCode,
              'phone': value.phone,
              'alternativeContact': value.alternativeContact,
            },
          );

          if (!context.mounted) return;
          if (!result.isSuccess || result.value == null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(result.messageKey)));
            return;
          }

          Navigator.of(context).pop();
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LandParcelDetailScreen(
                controller: deps.controller,
                parcelId: result.value!.id,
                onGpsRequested: () =>
                    _measureGps(context, deps, result.value!.id),
                onImportRequested: () =>
                    _import(context, deps, result.value!.id),
                onEditRequested: () =>
                    _editParcel(context, deps, result.value!.id),
              ),
            ),
          );
        },
      ),
    ),
  );

  Future<LandParcelBoundaryDraft?> _measureGpsForCreate(
    BuildContext context,
  ) async {
    final measured = await Navigator.of(context).push<FieldModel>(
      MaterialPageRoute(
        builder: (_) => const FieldGpsMeasureScreen(persistResult: false),
      ),
    );
    if (!context.mounted || measured == null) return null;

    try {
      final vertices = measured.polygon
          .map(
            (point) => Wgs84Vertex(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
          )
          .toList();
      return LandParcelBoundaryDraft(
        boundary: Wgs84Polygon.fromVertices(vertices),
        source: BoundarySource.gps,
      );
    } on FormatException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('parcel.boundaryRequired'))),
        );
      }
      return null;
    }
  }

  Future<LandParcelBoundaryDraft?> _importForCreate(
    BuildContext context,
    _V2Dependencies deps,
  ) async {
    try {
      final selected = await deps.platform.pickKmlOrKmz();
      if (!context.mounted || selected == null) return null;

      final result = selected.isKmz
          ? deps.controller.previewKmz(selected.bytes)
          : deps.controller.previewKml(utf8.decode(selected.bytes));

      if (!result.isSuccess ||
          result.value == null ||
          result.value!.previews.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.text('landParcel.import.failed')),
            ),
          );
        }
        return null;
      }

      final preview = result.value!.previews.first;
      return LandParcelBoundaryDraft(
        boundary: preview.boundary,
        source: BoundarySource.googleEarth,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.text('landParcel.import.failed')),
          ),
        );
      }
      return null;
    }
  }
}

class _V2Dependencies {
  const _V2Dependencies({
    required this.subject,
    required this.spatial,
    required this.controller,
    required this.platform,
  });
  final AuthorizationSubject subject;
  final SpatialPersistenceComposition spatial;
  final LandParcelController controller;
  final MobileLandParcelPlatformGateway platform;
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${context.l10n.text('startup.error')}\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
