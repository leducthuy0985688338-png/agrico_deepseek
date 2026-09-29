class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.farmId,
    required this.code,
    required this.name,
    required this.unit,
    required this.unitPrice,
    required this.supplier,
    this.stock = 0,
  });

  final String id;
  final String farmId;
  final String code;
  final String name;
  final String unit;
  final double unitPrice;
  final String supplier;
  final int stock;

  void validate() {
    if ([id, farmId, code, name, unit].any((value) => value.trim().isEmpty) ||
        !unitPrice.isFinite ||
        unitPrice < 0 ||
        stock < 0) {
      throw const FormatException('Invalid inventory item.');
    }
  }
}

enum InventoryMovementKind { receipt, issue }

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.farmId,
    required this.itemId,
    required this.kind,
    required this.quantity,
    required this.occurredAt,
  });

  final String id;
  final String farmId;
  final String itemId;
  final InventoryMovementKind kind;
  final int quantity;
  final DateTime occurredAt;

  void validate() {
    if ([id, farmId, itemId].any((value) => value.trim().isEmpty) ||
        quantity <= 0) {
      throw const FormatException('Invalid inventory movement.');
    }
  }
}
