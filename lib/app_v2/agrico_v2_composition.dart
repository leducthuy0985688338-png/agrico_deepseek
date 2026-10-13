import 'v2_resource_module_routes.dart';
import '../features/farm/presentation/screens/work_resource_catalog_screen.dart';
import '../features/farm/domain/entities/parcel_work.dart';
import '../features/inventory/application/inventory_service.dart';
import '../features/inventory/presentation/inventory_catalog_screen.dart';
import '../core/backup/local_backup_access.dart';
import '../core/backup/local_backup_screen.dart';
import '../core/auth/admin/company_account_admin_screen.dart';
import '../core/auth/admin/company_account_admin_service.dart';
import '../core/auth/admin/firebase_company_account_admin_repository.dart';
import '../features/farm/application/production_parcel_creation_service.dart';
import '../features/farm/data/adapters/spatial_production_parcel_creation_repository.dart';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:sqflite/sqflite.dart';

import '../core/project/agrico_project.dart';
import '../core/localization/app_localizations.dart';
import '../core/geography/data/sqlite_administrative_catalog.dart';
import '../core/catalog/company_catalog.dart';
import '../core/catalog/sync/catalog_sync_screen.dart';
import '../core/catalog/sync/firebase_catalog_sync_workspace.dart';
import '../core/catalog/sqlite_company_catalog.dart';
import '../core/catalog/company_catalog_screen.dart';
import '../core/geography/application/manage_administrative_catalog.dart';
import '../core/geography/presentation/administrative_catalog_screen.dart';

import '../core/identity/data/sqlite_parcel_number_sequence.dart';
import '../core/identity/data/sqlite_production_parcel_number_allocator.dart';
import '../core/permissions/authorization.dart';
import '../core/spatial/data/identity/default_spatial_identity_generator.dart';
import '../core/spatial/data/spatial_persistence_composition.dart';
import '../features/farm/application/land_parcel_application_service.dart';
import '../features/farm/application/land_parcel_spatial_sync_workflow.dart';
import '../features/farm/data/adapters/default_land_parcel_spatial_projection.dart';
import '../features/farm/application/land_parcel_boundary_consistency_queries.dart';
import '../features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
import '../features/farm/data/adapters/land_parcel_spatial_transaction.dart';
import '../features/farm/data/interchange/kml_interchange.dart';
import '../features/farm/application/land_parcel_use_cases.dart';

import '../features/farm/data/local/sqlite_land_parcel_repository.dart';
import '../features/farm/data/local/sqlite_land_survey_repository.dart';
import '../features/farm/data/local/sqlite_parcel_work_repository.dart';
import '../features/farm/application/parcel_work_service.dart';
import '../features/farm/application/production_history_service.dart';
import '../features/farm/presentation/screens/production_history_screen.dart';
import '../features/farm/application/task_work_service.dart';
import '../features/farm/data/local/sqlite_task_work_repository.dart';
import '../features/farm/application/farm_task_service.dart';
import '../features/farm/data/local/sqlite_farm_task_repository.dart';

import '../features/inventory/data/local/sqlite_inventory_repository.dart';

import '../features/farm/presentation/controllers/farm_task_controller.dart';
import '../features/farm/presentation/screens/farm_task_screen.dart';

import '../features/farm/presentation/screens/parcel_work_screen.dart';
import '../features/farm/data/local/sqlite_parcel_land_history_repository.dart';
import '../features/farm/application/parcel_land_history_service.dart';
import '../features/farm/application/parcel_subdivision_service.dart';
import '../features/farm/presentation/screens/parcel_land_timeline_screen.dart';
import '../features/farm/presentation/screens/parcel_subdivision_screen.dart';
import '../features/farm/domain/entities/land_parcel.dart';
import '../features/farm/domain/entities/land_survey.dart';
import '../features/farm/domain/geometry/wgs84_geometry.dart';
import '../features/farm/presentation/controllers/land_parcel_controller.dart';
import '../features/farm/presentation/platform/land_parcel_platform_io.dart';
import '../features/farm/presentation/screens/land_parcel_detail_screen.dart';
import '../features/farm/application/land_parcel_parent_service.dart';
import '../features/farm/presentation/screens/land_parcel_form_screen.dart';
import '../features/farm/presentation/screens/land_parcel_list_screen.dart';
import '../features/farm/presentation/widgets/boundary_workflow_widgets.dart';
import '../features/finance/data/local/sqlite_finance_document_repository.dart';
import '../features/finance/application/finance_document_service.dart';
import '../features/finance/application/production_cost_summary.dart';
import '../features/finance/presentation/production_costs_screen.dart';
import '../features/finance/presentation/finance_documents_screen.dart';

import '../models/field_model.dart';

import '../screens/field_gps_measure_screen.dart';

import '../services/field_database.dart';
import 'agrico_app_shell.dart';
import 'v2_settings_screen.dart';

class AgricoV2Root extends StatefulWidget {
  const AgricoV2Root({
    super.key,
    required this.userId,
    required this.subject,
    required this.onSignOut,
    this.sessionOffline = false,
  });
  final AuthorizationSubject subject;
  final VoidCallback onSignOut;
  final bool sessionOffline;
  final String userId;
  @override
  State<AgricoV2Root> createState() => _AgricoV2RootState();
}

class _AgricoV2RootState extends State<AgricoV2Root> {
  late final Future<_V2Dependencies> dependencies = _bootstrap();

  Future<_V2Dependencies> _bootstrap() async {
    final subject = widget.subject;
    if (!subject.active ||
        subject.farmId != 'local-farm' ||
        subject.userId != widget.userId ||
        subject.validUntil == null ||
        !DateTime.now().isBefore(subject.validUntil!)) {
      throw StateError('Invalid company session.');
    }
    final sharedDatabase = FieldDatabase();
    final database = await sharedDatabase.database;
    final spatial = SpatialPersistenceComposition(database);
    await SqliteLandSurveyRepository.createSchema(database);
    await SqliteParcelNumberSequence.createSchema(database);
    await SqliteProductionParcelNumberAllocator.createSchema(database);
    await SqliteParcelWorkRepository.createSchema(database);
    await SqliteFarmTaskRepository.createSchema(database);
    await SqliteInventoryRepository.createSchema(database);
    await SqliteCompanyCatalog.createSchema(database);
    await SqliteCompanyCatalog(database).adoptExisting(subject.farmId);
    await SqliteParcelLandHistoryRepository.createSchema(database);
    await SqliteParcelNumberSequence.reconcileExistingHouseholds(database);
    await SqliteFinanceDocumentRepository.createSchema(database);
    await SqliteAdministrativeCatalog.createSchema(database);
    final administrativeCatalog = SqliteAdministrativeCatalog(database);
    await administrativeCatalog.seedInitialLocation();
    final finance = SqliteFinanceDocumentRepository(database);
    final parcels = SqliteLandParcelRepository(database);
    final spatialSyncWorkflow = LandParcelSpatialSyncWorkflow(
      transaction: LandParcelSpatialTransaction(database),
      projection: const DefaultLandParcelSpatialProjection(),
      identityGenerator: DefaultSpatialIdentityGenerator(),
    );
    final boundaryConsistencyQueries = LandParcelBoundaryConsistencyQueries(
      links: SqliteLandParcelSpatialLinkRepository(database),
      features: spatial.featureRepository,
      revisions: spatial.revisionRepository,
    );

    final application = LandParcelApplicationService(
      repository: parcels,
      spatialWorkflow: spatialSyncWorkflow,
      boundaryConsistencyQueries: boundaryConsistencyQueries,
      landSurveyRepository: SqliteLandSurveyRepository(database),
    );
    const platform = MobileLandParcelPlatformGateway();
    final productionCreation = ProductionParcelCreationService(
      SpatialProductionParcelCreationRepository(spatialSyncWorkflow),
    );
    final controller = LandParcelController(
      subject: subject,
      parcels: parcels,
      surveys: SqliteLandSurveyRepository(database),
      createLandParcel: CreateLandParcel(application),
      productionCreation: productionCreation,
      parentRelations: LandParcelParentService(parcels),
      replaceBoundary: ReplaceBoundary(application),
      updateMetadata: UpdateLandParcelMetadata(application),
      completeGpsMeasurement: CompleteGpsMeasurement(application),
      verifyBoundary: VerifyBoundary(application),
      importPreview: ImportKmlKmzPreview(application),
      applyImportedBoundary: ApplyImportedBoundary(application),
      exportKmlKmz: ExportKmlKmz(application),
      fileOpener: platform,
      googleEarthOpener: platform,
      boundaryConsistencyQueries: boundaryConsistencyQueries,
      reconcileLegacySpatialIdentity: ReconcileLegacySpatialIdentity(
        application,
      ),
    );
    await controller.loadList();
    final taskController = FarmTaskController(
      subject: subject,
      service: FarmTaskService(SqliteFarmTaskRepository(database)),
    );
    await taskController.load();
    return _V2Dependencies(
      subject: subject,
      spatial: spatial,
      spatialWorkflow: spatialSyncWorkflow,
      productionCreation: productionCreation,
      controller: controller,
      taskController: taskController,
      application: application,
      finance: finance,
      database: database,
      administrativeCatalog: ManageAdministrativeCatalog(administrativeCatalog),
      surveyRepository: SqliteLandSurveyRepository(database),
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
      final financeService = FinanceDocumentService(
        repository: deps.finance,
        parcels: deps.controller.parcels,
        subject: deps.subject,
        currentSubject: () => mounted ? widget.subject : null,
      );
      late final VoidCallback openParcels;
      Widget detail(String id) => LandParcelDetailScreen(
        landOnly: true,
        controller: deps.controller,
        parcelId: id,
        onFinanceRequested: financeService.canViewParcels
            ? () {
                final parcel = deps.controller.detail?.parcel;
                if (financeService.canViewParcels &&
                    parcel?.id == id &&
                    parcel?.farmId == financeService.organizationId) {
                  push(
                    FinanceDocumentsScreen(
                      service: financeService,
                      initialParcelId: id,
                    ),
                  );
                }
              }
            : null,
        onTimelineRequested: () => push(
          ParcelLandTimelineScreen(
            parcelId: id,
            subject: deps.subject,
            parcels: deps.controller.parcels,
            onSubdivisionSaved: deps.controller.loadList,
            onSubdivideRequested: () => ParcelSubdivisionScreen(
              productionPlots: true,
              catalog: CompanyCatalogService(
                repository: SqliteCompanyCatalog(deps.database),
                subject: deps.subject,
              ),
              subject: deps.subject,
              sourceParcelId: id,
              service: ParcelSubdivisionService(
                parcels: deps.controller.parcels,
                workflow: deps.spatialWorkflow,
                productionCreation: deps.productionCreation,
              ),
              administrativeCatalog: SqliteAdministrativeCatalog(deps.database),
            ),
            service: ParcelLandHistoryService(
              SqliteParcelLandHistoryRepository(deps.database),
              deps.controller.parcels,
            ),
          ),
        ),
        onTasksRequested:
            const AuthorizationService().can(
              subject: deps.subject,
              permission: PermissionCodes.taskView,
              resource: ResourceContext(farmId: deps.subject.farmId),
            )
            ? () => push(
                FarmTaskScreen(
                  controller: deps.taskController,
                  taskWork: TaskWorkService(
                    SqliteTaskWorkRepository(deps.database),
                  ),
                  initialParcelId: id,
                  parcels: deps.controller.items
                      .map((item) => item.parcel)
                      .toList(),
                  resources: ParcelWorkService(
                    SqliteParcelWorkRepository(deps.database),
                    catalog: CompanyCatalogService(
                      repository: SqliteCompanyCatalog(deps.database),
                      subject: deps.subject,
                    ),
                  ),
                ),
              )
            : null,
        onWorkRequested: () => push(
          ParcelWorkScreen(
            parcelId: id,
            subject: deps.subject,
            service: ParcelWorkService(
              SqliteParcelWorkRepository(deps.database),
              catalog: CompanyCatalogService(
                repository: SqliteCompanyCatalog(deps.database),
                subject: deps.subject,
              ),
            ),
          ),
        ),
        onGpsRequested: () => _measureGps(context, deps, id),
        onImportRequested: () => _import(context, deps, id),
        onEditRequested: () => _editParcel(context, deps, id),
        onAttachRequested: () => _attachParcel(context, deps, id),
        onOpenAttachment: (attachment) async {
          final reference = attachment.localReference;
          final opened =
              reference != null &&
              await deps.platform.openLocalAttachment(reference);
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.text('attachment.openFailed')),
              ),
            );
          }
        },
      );
      openParcels = () => push(
        LandParcelListScreen(
          landOnly: true,
          controller: deps.controller,
          onCreate: () => _createParcel(context, deps),
          detailBuilder: (_, id) => detail(id),
        ),
      );
      final legacy = <String, VoidCallback>{
        'tasks': () => push(
          FarmTaskScreen(
            controller: deps.taskController,
            taskWork: TaskWorkService(SqliteTaskWorkRepository(deps.database)),
            parcels: deps.controller.items.map((item) => item.parcel).toList(),
            resources: ParcelWorkService(
              SqliteParcelWorkRepository(deps.database),
              catalog: CompanyCatalogService(
                repository: SqliteCompanyCatalog(deps.database),
                subject: deps.subject,
              ),
            ),
          ),
        ),
        'settings': () => push(
          V2SettingsScreen(
            onSignOut: widget.onSignOut,
            onOpenCatalog:
                const AuthorizationService().can(
                  subject: deps.subject,
                  permission: PermissionCodes.catalogView,
                  resource: ResourceContext(farmId: deps.subject.farmId),
                )
                ? () => push(
                    CompanyCatalogScreen(
                      service: CompanyCatalogService(
                        repository: SqliteCompanyCatalog(deps.database),
                        subject: deps.subject,
                      ),
                    ),
                  )
                : null,
            onOpenCatalogSync:
                const AuthorizationService().can(
                      subject: widget.subject,
                      permission: PermissionCodes.cloudSync,
                      resource: ResourceContext(farmId: widget.subject.farmId),
                    ) &&
                    const AuthorizationService().can(
                      subject: widget.subject,
                      permission: PermissionCodes.catalogView,
                      resource: ResourceContext(farmId: widget.subject.farmId),
                    )
                ? () => push(
                    CatalogSyncScreen(
                      actions: firebaseCatalogSyncWorkspace(
                        database: deps.database,
                        currentSubject: () => mounted ? widget.subject : null,
                      ),
                    ),
                  )
                : null,
            onOpenBackup:
                LocalBackupAccess(
                  currentSubject: () => mounted ? widget.subject : null,
                ).canOpen
                ? () => push(
                    LocalBackupScreen(
                      database: deps.database,
                      access: LocalBackupAccess(
                        currentSubject: () => mounted ? widget.subject : null,
                      ),
                    ),
                  )
                : null,
            onOpenAccounts:
                const AuthorizationService().can(
                  subject: deps.subject,
                  permission: PermissionCodes.accountView,
                  resource: ResourceContext(farmId: deps.subject.farmId),
                )
                ? () => push(
                    CompanyAccountAdminScreen(
                      service: CompanyAccountAdminService(
                        repository: FirebaseCompanyAccountAdminRepository(),
                        subject: deps.subject,
                      ),
                    ),
                  )
                : null,
            sessionOffline: widget.sessionOffline,
            offlineUntil: deps.subject.validUntil,
          ),
        ),
        if (deps.subject.permissionCodes.contains(
          PermissionCodes.administrativeCatalogManage,
        ))
          'administrativeCatalog': () => push(
            AdministrativeCatalogScreen(
              catalog: deps.administrativeCatalog,
              subject: deps.subject,
            ),
          ),
      };
      final resourceService = ParcelWorkService(
        SqliteParcelWorkRepository(deps.database),
        catalog: CompanyCatalogService(
          repository: SqliteCompanyCatalog(deps.database),
          subject: deps.subject,
        ),
      );
      legacy.addAll(
        v2ResourceModuleRoutes(
          subject: deps.subject,
          currentSubject: () => mounted ? widget.subject : null,
          openMachines: () => push(
            WorkResourceCatalogScreen(
              kind: WorkResourceKind.machine,
              subject: deps.subject,
              service: resourceService,
            ),
          ),
          openWorkers: () => push(
            WorkResourceCatalogScreen(
              kind: WorkResourceKind.worker,
              subject: deps.subject,
              service: resourceService,
            ),
          ),
          openInventory: () => push(
            InventoryCatalogScreen(
              subject: deps.subject,
              service: InventoryService(
                SqliteInventoryRepository(deps.database),
              ),
            ),
          ),
          openBackup: () => push(
            LocalBackupScreen(
              database: deps.database,
              access: LocalBackupAccess(
                currentSubject: () => mounted ? widget.subject : null,
              ),
            ),
          ),
        ),
      );
      final historyService = ProductionHistoryService(
        work: SqliteParcelWorkRepository(deps.database),
        parcels: deps.controller.parcels,
        subject: deps.subject,
        currentSubject: () => mounted ? widget.subject : null,
      );
      if (historyService.canView) {
        legacy['productionLogs'] = () {
          if (historyService.canView) {
            push(
              ProductionHistoryScreen(
                service: historyService,
                openParcel: (parcel) {
                  if (historyService.canView) {
                    push(
                      ParcelWorkScreen(
                        parcelId: parcel.id,
                        subject: deps.subject,
                        service: historyService,
                        readOnly: true,
                        canView: () => historyService.canView,
                      ),
                    );
                  }
                },
              ),
            );
          }
        };
      }
      if (financeService.canView) {
        legacy['finance'] = () {
          if (financeService.canView) {
            push(FinanceDocumentsScreen(service: financeService));
          }
        };
      }
      final costService = ProductionCostSummary(financeService);
      if (costService.canView) {
        legacy['costs'] = () {
          if (costService.canView) {
            push(ProductionCostsScreen(service: costService));
          }
        };
      }
      // Unsupported routes stay closed until domain-level scope guards exist.
      if (!const AuthorizationService().can(
        subject: deps.subject,
        permission: PermissionCodes.taskView,
        resource: ResourceContext(farmId: deps.subject.farmId),
      )) {
        legacy.remove('tasks');
      }
      return AnimatedBuilder(
        animation: Listenable.merge([deps.controller, deps.taskController]),
        builder: (context, _) => AgricoAppShell(
          subject: deps.subject,
          landParcelController: deps.controller,
          openLandParcels: openParcels,
          openCreateParcel: () => _createParcel(context, deps),
          legacyRoutes: legacy,
          parcelCount:
              deps.controller.phase == ParcelPresentationPhase.persistenceError
              ? null
              : deps.controller.items.length,
          seasonCount: null,
          taskCount: deps.taskController.hasError
              ? null
              : deps.taskController.items.length,
        ),
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
      final preview = await showDialog<LandParcelImportPreview>(
        context: context,
        builder: (_) => KmlBoundaryPicker(previews: result.value!.previews),
      );
      if (!context.mounted || preview == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(),
            body: KmlImportPreviewView(
              controller: deps.controller,
              parcel: parcel,
              preview: preview,
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
          landOnly: true,
          catalog: CompanyCatalogService(
            repository: SqliteCompanyCatalog(deps.database),
            subject: deps.subject,
          ),
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
              crops: value.crops,
              expectedUpdatedAt: parcel.updatedAt,
              expectedCropUpdates: {
                for (final crop in data.crops) crop.id: crop.updatedAt,
              },
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

            final landUseResult = await deps.application.updateLandUseProfile(
              deps.subject,
              UpdateLandUseProfileCommand(
                farmId: deps.subject.farmId,
                parcelId: parcel.id,
                actorMembershipId: deps.subject.membershipId,
                occurredAt: DateTime.now().toUtc(),
                landUseType: value.landUseType,
                currentCondition: value.landCondition,
                clearingStatus: value.clearingStatus,
                readinessStatus: value.readinessStatus,
              ),
            );
            if (!landUseResult.isSuccess) {
              if (editContext.mounted) {
                ScaffoldMessenger.of(editContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      editContext.l10n.text(landUseResult.messageKey),
                    ),
                  ),
                );
              }
              return;
            }
            await deps.controller.loadDetail(parcel.id);
            if (!editContext.mounted) return;

            Navigator.of(editContext).pop();
          },
        ),
      ),
    );
  }

  Future<void> _attachParcel(
    BuildContext context,
    _V2Dependencies deps,
    String parcelId,
  ) async {
    if (!deps.controller.can(PermissionCodes.fieldEdit, parcelId: parcelId)) {
      return;
    }
    try {
      final picked = await deps.platform.pickAndStoreAttachment();
      if (picked == null) return;
      final name = picked.name.toLowerCase();
      final photo = [
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.heic',
      ].any(name.endsWith);
      final type = photo
          ? ParcelAttachmentType.photo
          : ParcelAttachmentType.document;
      final mime = photo
          ? (name.endsWith('.png')
                ? 'image/png'
                : name.endsWith('.webp')
                ? 'image/webp'
                : name.endsWith('.heic')
                ? 'image/heic'
                : 'image/jpeg')
          : name.endsWith('.pdf')
          ? 'application/pdf'
          : 'application/octet-stream';
      final now = DateTime.now().toUtc();
      await deps.surveyRepository.createAttachment(
        ParcelAttachment(
          id: 'attachment-${now.microsecondsSinceEpoch}',
          parcelId: parcelId,
          attachmentType: type,
          fileName: picked.name,
          mimeType: mime,
          localReference: picked.path,
          createdAt: now,
          createdBy: deps.subject.membershipId,
        ),
      );
      await deps.controller.loadDetail(parcelId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('attachment.saveFailed'))),
        );
      }
    }
  }

  void _createParcel(BuildContext context, _V2Dependencies deps) async {
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LandParcelFormScreen(
          landOnly: true,
          catalog: CompanyCatalogService(
            repository: SqliteCompanyCatalog(deps.database),
            subject: deps.subject,
          ),
          productionProjectId: AgricoProject.defaultProject.id,
          productionProjectCode: AgricoProject.defaultProject.code,
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

            final id =
                'parcel-${DateTime.now().toUtc().microsecondsSinceEpoch}';
            final result = await deps.controller.create(
              id: id,
              parcelCode: value.parcelCode,
              projectId: AgricoProject.defaultProject.id,
              projectCode: AgricoProject.defaultProject.code,
              productionKind: value.productionKind,
              name: value.name,
              vertices: draft.boundary.vertices.toList(),
              source: draft.source,
              ownerDisplayName: null,
              ownerHouseholdId: null,
              autoNumber: value.autoNumber,
              villageId: value.villageId,
              countryCode: value.countryCode,
              provinceCode: value.provinceCode,
              districtCode: value.districtCode,
              villageCode: value.villageCode,
              legacyMetadata: {
                'active': value.active,
                'country': value.country,
                'province': value.province,
                'district': value.district,
                'village': value.village,
                'countryCode': value.countryCode,
                'provinceCode': value.provinceCode,
                'districtCode': value.districtCode,
                'villageCode': value.villageCode,
              },
            );

            if (!context.mounted) return;
            if (!result.isSuccess || result.value == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.text(result.messageKey))),
              );
              return;
            }

            final createdId = result.value!.id;
            final landUseResult = await deps.application.updateLandUseProfile(
              deps.subject,
              UpdateLandUseProfileCommand(
                farmId: deps.subject.farmId,
                parcelId: createdId,
                actorMembershipId: deps.subject.membershipId,
                occurredAt: DateTime.now().toUtc(),
                landUseType: value.landUseType,
                currentCondition: value.landCondition,
                clearingStatus: value.clearingStatus,
                readinessStatus: value.readinessStatus,
              ),
            );
            if (!landUseResult.isSuccess) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.text(landUseResult.messageKey)),
                  ),
                );
              }
              return;
            }

            if (!context.mounted) return;

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
  }

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

      final preview = await showDialog<LandParcelImportPreview>(
        context: context,
        builder: (dialogContext) =>
            KmlBoundaryPicker(previews: result.value!.previews),
      );
      if (!context.mounted || preview == null) return null;
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
    required this.spatialWorkflow,
    required this.productionCreation,
    required this.controller,
    required this.taskController,
    required this.application,
    required this.finance,
    required this.database,
    required this.administrativeCatalog,
    required this.surveyRepository,
    required this.platform,
  });
  final AuthorizationSubject subject;
  final SpatialPersistenceComposition spatial;
  final LandParcelSpatialSyncWorkflow spatialWorkflow;
  final ProductionParcelCreationService productionCreation;
  final LandParcelController controller;
  final FarmTaskController taskController;
  final LandParcelApplicationService application;
  final SqliteFinanceDocumentRepository finance;
  final Database database;
  final ManageAdministrativeCatalog administrativeCatalog;
  final SqliteLandSurveyRepository surveyRepository;
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
