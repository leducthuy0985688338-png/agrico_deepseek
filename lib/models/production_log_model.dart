class ProductionLogModel {
  final String id;
  final String seasonId;
  final String fieldId;
  final DateTime date;
  final String activityType;
  final String title;
  final double quantity;
  final String unit;
  final double cost;
  final String worker;
  final String notes;

  const ProductionLogModel({
    required this.id,
    required this.seasonId,
    required this.fieldId,
    required this.date,
    required this.activityType,
    required this.title,
    this.quantity = 0,
    this.unit = '',
    this.cost = 0,
    this.worker = '',
    this.notes = '',
  });

  factory ProductionLogModel.fromJson(Map<String, dynamic> json) => ProductionLogModel(
        id: json['id'] as String,
        seasonId: json['seasonId'] as String,
        fieldId: json['fieldId'] as String,
        date: DateTime.parse(json['date'] as String),
        activityType: json['activityType'] as String,
        title: json['title'] as String,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] as String? ?? '',
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        worker: json['worker'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'seasonId': seasonId,
        'fieldId': fieldId,
        'date': date.toIso8601String(),
        'activityType': activityType,
        'title': title,
        'quantity': quantity,
        'unit': unit,
        'cost': cost,
        'worker': worker,
        'notes': notes,
      };
}
