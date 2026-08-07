class MachineModel {
  final String id;
  final String name;
  final String type;
  final String manufacturer;
  final int year;
  String status;
  int totalHours;
  double fuelConsumption;
  String? currentFieldId; // Lô đất đang làm việc (null nếu không làm)
  List<MaintenanceRecord> maintenanceHistory;
  List<MachineFieldRecord> fieldHistory; // Lịch sử làm việc trên các lô

  MachineModel({
    required this.id,
    required this.name,
    required this.type,
    required this.manufacturer,
    required this.year,
    required this.status,
    this.totalHours = 0,
    this.fuelConsumption = 0,
    this.currentFieldId,
    this.maintenanceHistory = const [],
    this.fieldHistory = const [],
  });

  // Hàm copyWith để tạo bản sao mới
  MachineModel copyWith({
    String? status,
    int? totalHours,
    double? fuelConsumption,
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
      currentFieldId: currentFieldId ?? this.currentFieldId,
      maintenanceHistory: maintenanceHistory ?? this.maintenanceHistory,
      fieldHistory: fieldHistory ?? this.fieldHistory,
    );
  }
}

// Model cho bảo trì
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

// Model cho lịch sử làm việc trên lô đất
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
