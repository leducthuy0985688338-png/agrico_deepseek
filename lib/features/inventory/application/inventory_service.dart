import '../../../core/permissions/authorization.dart';
import '../domain/entities/inventory_item.dart';
import '../domain/repositories/inventory_repository.dart';
import '../domain/repositories/production_destination_repository.dart';

class InventoryService {
  const InventoryService(this.repository);

  final InventoryRepository repository;

  void _authorize(AuthorizationSubject subject, String permission) {
    if (!subject.dataScopes.contains(DataScope.allFarm) ||
        !const AuthorizationService().can(
          subject: subject,
          permission: permission,
          resource: ResourceContext(farmId: subject.farmId),
        )) {
      throw StateError('Inventory requires farm-wide access.');
    }
  }

  Future<List<InventoryItem>> list(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.inventoryView);
    return repository.listByFarm(subject.farmId);
  }

  Future<List<InventoryMovement>> movements(AuthorizationSubject subject) {
    _authorize(subject, PermissionCodes.inventoryView);
    return repository.movementsByFarm(subject.farmId);
  }

  Future<void> register(AuthorizationSubject subject, InventoryItem item) {
    _authorize(subject, PermissionCodes.catalogManage);
    if (item.farmId != subject.farmId) {
      throw StateError('Item is outside the current farm.');
    }
    item.validate();
    return repository.register(item);
  }

  ProductionDestinationRepository get _destinations {
    final store = repository;
    if (store is! ProductionDestinationRepository) {
      throw StateError('Production destinations are unavailable.');
    }
    return store as ProductionDestinationRepository;
  }

  Future<List<ProductionDestination>> productionDestinations(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryManage);
    return _destinations.productionDestinations(subject.farmId);
  }

  Future<List<ProductionIdentityChoice>> productionParcels(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    return _destinations.productionParcels(subject.farmId);
  }

  Future<List<ProductionSeason>> productionSeasons(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.inventoryView);
    return _destinations.productionSeasons(subject.farmId);
  }

  Future<List<ProductionMaterialCost>> productionCosts(
    AuthorizationSubject subject,
  ) {
    _authorize(subject, PermissionCodes.financeView);
    return _destinations.productionCosts(subject.farmId);
  }

  Future<void> createProductionSeason(
    AuthorizationSubject subject,
    ProductionSeason season,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    if (season.farmId != subject.farmId) {
      throw StateError('Season is outside this farm.');
    }
    season.validate();
    return _destinations.createProductionSeason(season);
  }

  Future<void> setProductionSeasonActive(
    AuthorizationSubject subject,
    String seasonId,
    bool active,
  ) {
    _authorize(subject, PermissionCodes.productionPlan);
    return _destinations.setProductionSeasonActive(
      subject.farmId,
      seasonId,
      active,
    );
  }

  /// Production issues require an explicit destination and a SQLite-backed
  /// repository whose contract commits stock and production cost atomically.
  Future<void> recordProductionIssue(
    AuthorizationSubject subject,
    InventoryMovement movement, {
    required String parcelId,
    required String seasonId,
  }) {
    _authorize(subject, PermissionCodes.inventoryManage);
    if (movement.farmId != subject.farmId) {
      throw StateError('Movement is outside the current farm.');
    }
    movement.validate();
    return _destinations.recordProductionIssue(
      movement,
      parcelId: parcelId,
      seasonId: seasonId,
    );
  }

  Future<void> record(
    AuthorizationSubject subject,
    InventoryMovement movement,
  ) {
    _authorize(subject, PermissionCodes.inventoryManage);
    if (movement.farmId != subject.farmId) {
      throw StateError('Movement is outside the current farm.');
    }
    movement.validate();
    return repository.record(movement);
  }
}
