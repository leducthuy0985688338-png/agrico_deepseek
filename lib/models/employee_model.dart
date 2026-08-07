class EmployeeModel {
  final String id;
  final String name;
  final String position; // Vị trí: Quản lý, Công nhân, Kỹ sư,...
  final String department; // Bộ phận: Sản xuất, Kho, Văn phòng,...
  final double dailyRate; // Lương theo ngày (VND)
  final String phone;
  final String? address;
  bool isActive;

  EmployeeModel({
    required this.id,
    required this.name,
    required this.position,
    required this.department,
    required this.dailyRate,
    required this.phone,
    this.address,
    this.isActive = true,
  });

  // Copy with method
  EmployeeModel copyWith({
    String? name,
    String? position,
    String? department,
    double? dailyRate,
    String? phone,
    String? address,
    bool? isActive,
  }) {
    return EmployeeModel(
      id: id,
      name: name ?? this.name,
      position: position ?? this.position,
      department: department ?? this.department,
      dailyRate: dailyRate ?? this.dailyRate,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
    );
  }
}

// Model cho chấm công
class AttendanceRecord {
  final String employeeId;
  final DateTime date;
  final DateTime checkIn;
  final DateTime? checkOut;
  final double hours; // Số giờ làm việc
  final String? fieldId; // Lô đất làm việc (nếu có)

  AttendanceRecord({
    required this.employeeId,
    required this.date,
    required this.checkIn,
    this.checkOut,
    required this.hours,
    this.fieldId,
  });
}

// Model cho bảng lương
class PayrollRecord {
  final String employeeId;
  final String employeeName;
  final int month; // Tháng
  final int year; // Năm
  final int workingDays; // Số ngày công
  final double totalSalary; // Tổng lương
  final double? bonus; // Thưởng
  final double? deduction; // Khấu trừ (nếu có)
  final double netSalary; // Lương thực lĩnh

  PayrollRecord({
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.year,
    required this.workingDays,
    required this.totalSalary,
    this.bonus,
    this.deduction,
    required this.netSalary,
  });
}
