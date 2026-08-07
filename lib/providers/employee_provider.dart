import 'package:flutter/material.dart';
import '../models/employee_model.dart';

class EmployeeProvider extends ChangeNotifier {
  List<EmployeeModel> _employees = [];
  List<AttendanceRecord> _attendanceLogs = [];
  List<PayrollRecord> _payrollRecords = [];

  List<EmployeeModel> get employees => _employees;
  List<AttendanceRecord> get attendanceLogs => _attendanceLogs;
  List<PayrollRecord> get payrollRecords => _payrollRecords;

  // Dữ liệu mẫu
  EmployeeProvider() {
    _employees = [
      EmployeeModel(
        id: 'NV001',
        name: 'Nguyễn Văn An',
        position: 'Công nhân',
        department: 'Sản xuất',
        dailyRate: 250000,
        phone: '0987654321',
        address: 'Hà Nội',
      ),
      EmployeeModel(
        id: 'NV002',
        name: 'Trần Thị Bình',
        position: 'Công nhân',
        department: 'Sản xuất',
        dailyRate: 250000,
        phone: '0976543210',
        address: 'Hà Nội',
      ),
      EmployeeModel(
        id: 'NV003',
        name: 'Lê Văn Cường',
        position: 'Quản lý sản xuất',
        department: 'Sản xuất',
        dailyRate: 500000,
        phone: '0965432109',
        address: 'Hà Nội',
      ),
      EmployeeModel(
        id: 'NV004',
        name: 'Phạm Thị Dung',
        position: 'Kế toán',
        department: 'Văn phòng',
        dailyRate: 400000,
        phone: '0954321098',
        address: 'Hà Nội',
      ),
      EmployeeModel(
        id: 'NV005',
        name: 'Hoàng Văn Em',
        position: 'Lái máy',
        department: 'Sản xuất',
        dailyRate: 350000,
        phone: '0943210987',
        address: 'Hà Nội',
      ),
    ];

    // Dữ liệu chấm công mẫu (tháng hiện tại)
    final now = DateTime.now();
    for (var employee in _employees) {
      for (int day = 1; day <= 5; day++) {
        _attendanceLogs.add(
          AttendanceRecord(
            employeeId: employee.id,
            date: DateTime(now.year, now.month, day),
            checkIn: DateTime(now.year, now.month, day, 7, 30),
            checkOut: DateTime(now.year, now.month, day, 17, 0),
            hours: 8.5,
            fieldId: 'LO0001',
          ),
        );
      }
    }
  }

  // Thêm nhân viên
  void addEmployee(EmployeeModel employee) {
    _employees.add(employee);
    notifyListeners();
  }

  // Cập nhật nhân viên
  void updateEmployee(EmployeeModel updated) {
    final index = _employees.indexWhere((e) => e.id == updated.id);
    if (index != -1) {
      _employees[index] = updated;
      notifyListeners();
    }
  }

  // Xóa nhân viên
  void removeEmployee(String id) {
    _employees.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  // Chấm công (Check-in)
  void checkIn(String employeeId, {String? fieldId}) {
    final now = DateTime.now();
    _attendanceLogs.add(
      AttendanceRecord(
        employeeId: employeeId,
        date: now,
        checkIn: now,
        hours: 0,
        fieldId: fieldId,
      ),
    );
    notifyListeners();
  }

  // Chấm công (Check-out)
  void checkOut(String employeeId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Tìm bản ghi chấm công hôm nay chưa check-out
    final index = _attendanceLogs.indexWhere(
      (record) =>
          record.employeeId == employeeId &&
          record.date.year == today.year &&
          record.date.month == today.month &&
          record.date.day == today.day &&
          record.checkOut == null,
    );

    if (index != -1) {
      final record = _attendanceLogs[index];
      final hours = now.difference(record.checkIn).inMinutes / 60.0;
      _attendanceLogs[index] = AttendanceRecord(
        employeeId: record.employeeId,
        date: record.date,
        checkIn: record.checkIn,
        checkOut: now,
        hours: hours,
        fieldId: record.fieldId,
      );
      notifyListeners();
    } else {
      // Nếu chưa check-in, tự động check-in và check-out
      checkIn(employeeId);
      // Đợi 1 giây rồi check-out (mô phỏng)
      Future.delayed(const Duration(seconds: 1), () {
        checkOut(employeeId);
      });
    }
  }

  // Tính lương cho một nhân viên trong tháng
  PayrollRecord calculatePayroll(String employeeId, int month, int year) {
    final employee = _employees.firstWhere((e) => e.id == employeeId);

    // Đếm số ngày công trong tháng
    final workingDays = _attendanceLogs
        .where(
          (record) =>
              record.employeeId == employeeId &&
              record.date.year == year &&
              record.date.month == month &&
              record.checkOut != null,
        )
        .length;

    final totalSalary = workingDays * employee.dailyRate;
    final netSalary = totalSalary; // Chưa có khấu trừ

    return PayrollRecord(
      employeeId: employeeId,
      employeeName: employee.name,
      month: month,
      year: year,
      workingDays: workingDays,
      totalSalary: totalSalary,
      netSalary: netSalary,
    );
  }

  // Tính lương cho tất cả nhân viên trong tháng
  void generatePayroll(int month, int year) {
    _payrollRecords.clear();
    for (var employee in _employees) {
      final record = calculatePayroll(employee.id, month, year);
      _payrollRecords.add(record);
    }
    notifyListeners();
  }

  // Lấy danh sách nhân viên theo bộ phận
  List<EmployeeModel> getEmployeesByDepartment(String department) {
    return _employees.where((e) => e.department == department).toList();
  }

  // Lấy lịch sử chấm công của một nhân viên
  List<AttendanceRecord> getAttendanceHistory(String employeeId) {
    return _attendanceLogs
        .where((record) => record.employeeId == employeeId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }
}
