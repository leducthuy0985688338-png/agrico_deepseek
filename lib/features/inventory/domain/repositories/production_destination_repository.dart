import '../entities/inventory_item.dart';

class ProductionDestination {
  const ProductionDestination({
    required this.parcelId,
    required this.parcelCode,
    required this.seasonId,
    required this.seasonName,
  });
  final String parcelId;
  final String parcelCode;
  final String seasonId;
  final String seasonName;
}

class ProductionIdentityChoice {
  const ProductionIdentityChoice(this.id, this.label);
  final String id;
  final String label;
}

class ProductionSeason {
  const ProductionSeason({
    required this.id,
    required this.farmId,
    required this.parcelId,
    required this.name,
    required this.startsOn,
    this.active = true,
  });
  final String id;
  final String farmId;
  final String parcelId;
  final String name;

  /// ISO calendar date in Laos (YYYY-MM-DD), not a device-local instant.
  final String startsOn;
  final bool active;

  void validate() {
    final parsed = DateTime.tryParse(startsOn);
    if ([id, farmId, parcelId, name].any((s) => s.trim().isEmpty) ||
        name != name.trim() ||
        name.length > 120 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(startsOn) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != startsOn) {
      throw const FormatException('Invalid production season.');
    }
  }
}

class ProductionMaterialCost {
  const ProductionMaterialCost({
    required this.movementId,
    required this.parcelId,
    required this.parcelCode,
    required this.seasonId,
    required this.seasonName,
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    required this.occurredAt,
  });
  final String movementId;
  final String parcelId;
  final String parcelCode;
  final String seasonId;
  final String seasonName;
  final String itemName;
  final String unit;
  final int quantity;
  final double unitPrice;
  final double amount;
  final DateTime occurredAt;
}

abstract interface class ProductionDestinationRepository {
  /// Movement, stock, numbering and cost snapshot commit together or not at all.
  Future<void> recordProductionIssue(
    InventoryMovement movement, {
    required String parcelId,
    required String seasonId,
  });
  Future<List<ProductionDestination>> productionDestinations(String farmId);
  Future<List<ProductionIdentityChoice>> productionParcels(String farmId);
  Future<List<ProductionSeason>> productionSeasons(String farmId);
  Future<void> createProductionSeason(ProductionSeason season);
  Future<void> setProductionSeasonActive(
    String farmId,
    String seasonId,
    bool active,
  );
  Future<List<ProductionMaterialCost>> productionCosts(String farmId);
}
