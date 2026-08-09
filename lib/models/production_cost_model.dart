enum ProductionCostCategory { material, labor, machine, fuel }

extension ProductionCostCategoryX on ProductionCostCategory {
  String get label {
    switch (this) {
      case ProductionCostCategory.material:
        return 'Vật tư';
      case ProductionCostCategory.labor:
        return 'Nhân công';
      case ProductionCostCategory.machine:
        return 'Máy móc';
      case ProductionCostCategory.fuel:
        return 'Nhiên liệu';
    }
  }

  String get key => name;

  static ProductionCostCategory fromKey(String value) {
    return ProductionCostCategory.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ProductionCostCategory.material,
    );
  }
}

class ProductionCostModel {
  final String id;
  final String fieldId;
  final String seasonId;
  final ProductionCostCategory category;
  final DateTime date;
  final String itemName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double amount;
  final String? employeeId;
  final String? machineId;
  final String notes;
  final String? source;
  final String? sourceId;

  const ProductionCostModel({
    required this.id,
    required this.fieldId,
    required this.seasonId,
    required this.category,
    required this.date,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.amount,
    this.employeeId,
    this.machineId,
    this.notes = '',
    this.source,
    this.sourceId,
  });

  factory ProductionCostModel.fromJson(Map<String, dynamic> json) {
    return ProductionCostModel(
      id: json['id'] as String,
      fieldId: json['fieldId'] as String,
      seasonId: json['seasonId'] as String,
      category: ProductionCostCategoryX.fromKey(json['category'] as String? ?? 'material'),
      date: DateTime.parse(json['date'] as String),
      itemName: json['itemName'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      unitPrice: (json['unitPrice'] as num).toDouble(),
      amount: (json['amount'] as num).toDouble(),
      employeeId: json['employeeId'] as String?,
      machineId: json['machineId'] as String?,
      notes: json['notes'] as String? ?? '',
      source: json['source'] as String?,
      sourceId: json['sourceId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fieldId': fieldId,
        'seasonId': seasonId,
        'category': category.key,
        'date': date.toIso8601String(),
        'itemName': itemName,
        'quantity': quantity,
        'unit': unit,
        'unitPrice': unitPrice,
        'amount': amount,
        'employeeId': employeeId,
        'machineId': machineId,
        'notes': notes,
        'source': source,
        'sourceId': sourceId,
      };
}
