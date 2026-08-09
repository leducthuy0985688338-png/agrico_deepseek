class HarvestRecordModel {
  final String id;
  final String seasonId;
  final String fieldId;
  final DateTime date;
  final double quantity;
  final String unit;
  final double moisturePercent;
  final double sellingPrice;
  final double revenue;
  final String notes;

  const HarvestRecordModel({
    required this.id,
    required this.seasonId,
    required this.fieldId,
    required this.date,
    required this.quantity,
    this.unit = 'kg',
    this.moisturePercent = 0,
    this.sellingPrice = 0,
    this.revenue = 0,
    this.notes = '',
  });

  factory HarvestRecordModel.fromJson(Map<String, dynamic> json) => HarvestRecordModel(
        id: json['id'] as String,
        seasonId: json['seasonId'] as String,
        fieldId: json['fieldId'] as String,
        date: DateTime.parse(json['date'] as String),
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'] as String? ?? 'kg',
        moisturePercent: (json['moisturePercent'] as num?)?.toDouble() ?? 0,
        sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
        notes: json['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'seasonId': seasonId,
        'fieldId': fieldId,
        'date': date.toIso8601String(),
        'quantity': quantity,
        'unit': unit,
        'moisturePercent': moisturePercent,
        'sellingPrice': sellingPrice,
        'revenue': revenue,
        'notes': notes,
      };
}
