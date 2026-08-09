class ProductionSeasonModel {
  final String id;
  final String fieldId;
  final String name;
  final String crop;
  final String variety;
  final DateTime startDate;
  final DateTime? expectedHarvestDate;
  final String status;
  final double plannedArea;
  final String notes;

  const ProductionSeasonModel({
    required this.id,
    required this.fieldId,
    required this.name,
    required this.crop,
    required this.variety,
    required this.startDate,
    this.expectedHarvestDate,
    required this.status,
    required this.plannedArea,
    this.notes = '',
  });

  factory ProductionSeasonModel.fromJson(Map<String, dynamic> json) {
    return ProductionSeasonModel(
      id: json['id'] as String,
      fieldId: json['fieldId'] as String,
      name: json['name'] as String,
      crop: json['crop'] as String,
      variety: json['variety'] as String? ?? '',
      startDate: DateTime.parse(json['startDate'] as String),
      expectedHarvestDate: json['expectedHarvestDate'] == null
          ? null
          : DateTime.parse(json['expectedHarvestDate'] as String),
      status: json['status'] as String? ?? 'Đang sản xuất',
      plannedArea: (json['plannedArea'] as num).toDouble(),
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fieldId': fieldId,
        'name': name,
        'crop': crop,
        'variety': variety,
        'startDate': startDate.toIso8601String(),
        'expectedHarvestDate': expectedHarvestDate?.toIso8601String(),
        'status': status,
        'plannedArea': plannedArea,
        'notes': notes,
      };

  ProductionSeasonModel copyWith({
    String? id,
    String? fieldId,
    String? name,
    String? crop,
    String? variety,
    DateTime? startDate,
    DateTime? expectedHarvestDate,
    String? status,
    double? plannedArea,
    String? notes,
  }) {
    return ProductionSeasonModel(
      id: id ?? this.id,
      fieldId: fieldId ?? this.fieldId,
      name: name ?? this.name,
      crop: crop ?? this.crop,
      variety: variety ?? this.variety,
      startDate: startDate ?? this.startDate,
      expectedHarvestDate: expectedHarvestDate ?? this.expectedHarvestDate,
      status: status ?? this.status,
      plannedArea: plannedArea ?? this.plannedArea,
      notes: notes ?? this.notes,
    );
  }
}
