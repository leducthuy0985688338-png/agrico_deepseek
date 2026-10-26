import 'exact_decimal.dart';

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
    this.finishedGoods = false,
  });

  final String id;
  final String farmId;
  final String code;
  final String name;
  final String unit;
  final double unitPrice;
  final String supplier;
  final num stock;
  final bool finishedGoods;

  void validate() {
    if ([id, farmId, code, name, unit].any((value) => value.trim().isEmpty) ||
        !unitPrice.isFinite ||
        unitPrice < 0 ||
        stock < 0 ||
        ExactDecimal.quantityUnits(stock) < 0) {
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
    this.code,
    this.unitPriceText,
    this.currency,
    this.pricedBy,
    this.zeroPriceConfirmed = false,
  });

  final String id;
  final String farmId;
  final String itemId;
  final InventoryMovementKind kind;
  final num quantity;
  final String? unitPriceText;
  final String? currency;
  final String? pricedBy;
  final bool zeroPriceConfirmed;
  int get quantityUnits => ExactDecimal.quantityUnits(quantity);
  String? get amountText => unitPriceText == null
      ? null
      : (ExactDecimal.parse(quantity.toString()) *
                ExactDecimal.parse(unitPriceText!))
            .toString();
  InventoryMovement withPricedBy(String userId) => InventoryMovement(
    id: id,
    farmId: farmId,
    itemId: itemId,
    kind: kind,
    quantity: quantity,
    occurredAt: occurredAt,
    code: code,
    unitPriceText: unitPriceText,
    currency: currency,
    pricedBy: userId,
    zeroPriceConfirmed: zeroPriceConfirmed,
  );
  final DateTime occurredAt;

  /// Assigned by the repository; older movements may have no document code.
  final String? code;

  void validate() {
    if ([id, farmId, itemId].any((value) => value.trim().isEmpty) ||
        quantity <= 0 ||
        quantityUnits <= 0) {
      throw const FormatException('Invalid inventory movement.');
    }
    if (unitPriceText != null || currency != null) {
      ExactDecimal.validatePrice(unitPriceText ?? '', currency ?? '');
    }
  }
}
