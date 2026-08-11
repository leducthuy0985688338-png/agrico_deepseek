class MachineModel {
  final String id;
  final String name;
  final String type;
  final String manufacturer;
  final int year;
  String status;
  int totalHours;
  double fuelConsumption;
  /// Direct operating/depreciation rate used for production costing.
  /// Zero means the rate has not been configured yet.
  double costPerHour;
  String? currentFieldId;
  List<MaintenanceRecord> maintenanceHistory;
  List<MachineFieldRecord> fieldHistory;

  MachineModel({
    required this.id,
    required this.name,
    required this.type,
    required this.manufacturer,
    required this.year,
    required this.status,
    this.totalHours = 0,
    this.fuelConsumption = 0,
    this.costPerHour = 0,
    this.currentFieldId,
    this.maintenanceHistory = const [],
    this.fieldHistory = const [],
  });

  MachineModel copyWith({
    String? status,
    int? totalHours,
    double? fuelConsumption,
    double? costPerHour,
    String? currentFieldId,
    List<MaintenanceRecord>? maintenanceHistory,
    List<MachineFieldRecord>? fieldHistory,
  }) {
    return MachineModel(
      id: id,
      name: name,
      type: type,
      manufacturer: manufacturer,
      year: year,
      status: status ?? this.status,
      totalHours: totalHours ?? this.totalHours,
      fuelConsumption: fuelConsumption ?? this.fuelConsumption,
      costPerHour: costPerHour ?? this.costPerHour,
      currentFieldId: currentFieldId ?? this.currentFieldId,
      maintenanceHistory: maintenanceHistory ?? this.maintenanceHistory,
      fieldHistory: fieldHistory ?? this.fieldHistory,
    );
  }

  factory MachineModel.fromMap(Map<String, dynamic> map) {
    return MachineModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      manufacturer: map['manufacturer']?.toString() ?? '',
      year: (map['year'] as num?)?.toInt() ?? 0,
      status: map['status']?.toString() ?? 'Tốt',
      totalHours: (map['totalHours'] as num?)?.toInt() ?? 0,
      fuelConsumption:
          (map['fuelConsumption'] as num?)?.toDouble() ?? 0,
      costPerHour: (map['costPerHour'] as num?)?.toDouble() ?? 0,
      currentFieldId: map['currentFieldId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'manufacturer': manufacturer,
        'year': year,
        'status': status,
        'totalHours': totalHours,
        'fuelConsumption': fuelConsumption,
        'costPerHour': costPerHour,
        'currentFieldId': currentFieldId,
      };
}

class MaintenanceRecord {
  final DateTime date;
  final String content;
  final double cost;
  final String? parts;

  MaintenanceRecord({
    required this.date,
    required this.content,
    required this.cost,
    this.parts,
  });
}

class MachineFieldRecord {
  final String fieldId;
  final String fieldName;
  final DateTime startDate;
  final DateTime? endDate;
  final double hoursWorked;
  final double fuelUsed;
  final String? operatorName;

  MachineFieldRecord({
    required this.fieldId,
    required this.fieldName,
    required this.startDate,
    this.endDate,
    required this.hoursWorked,
    required this.fuelUsed,
    this.operatorName,
  });
}
