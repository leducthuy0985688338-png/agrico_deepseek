import 'dart:async';

import 'package:flutter/material.dart';
import '../models/employee_model.dart';
import '../services/labor_production_cost_sync_service.dart';

class EmployeeProvider extends ChangeNotifier {
  List<EmployeeModel> _employees = [];
  List<AttendanceRecord> _attendanceLogs = [];
  List<PayrollRecord> _payrollRecords = [];

  final LaborProductionCostSyncService _laborCostSync =
      LaborProductionCostSyncService();

  List<EmployeeModel> get employees => _employees;
  List<AttendanceRecord> get attendanceLogs => _attendanceLogs;
  List<PayrollRecord> get payrollRecords => _payrollRecords;

  void addEmployee(EmployeeModel employee) {
    _employees.add(employee);
    notifyListeners();
  }

  void updateEmployee(EmployeeModel updated) {
    final index = _employees.indexWhere((e) => e.id == updated.id);
    if (index != -1) {
      _employees[index] = updated;
      notifyListeners();
    }
  }

  void removeEmployee(String id) {
    _employees.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void restoreFromCloud({required List<EmployeeModel> employees}) {
    if (employees.isEmpty) return;

    _employees = <String, EmployeeModel>{
      for (final employee in employees) employee.id: employee,
    }.values.toList(growable: false)..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

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

  void checkOut(String employeeId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

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
      final updated = AttendanceRecord(
        employeeId: record.employeeId,
        date: record.date,
        checkIn: record.checkIn,
        checkOut: now,
        hours: hours,
        fieldId: record.fieldId,
      );
      _attendanceLogs[index] = updated;

      final employee = getEmployeeById(employeeId);
      if (employee != null) {
        unawaited(_syncAttendanceToProductionCost(updated, employee));
      }
      notifyListeners();
    } else {
      checkIn(employeeId);
      Future.delayed(const Duration(seconds: 1), () => checkOut(employeeId));
    }
  }

  EmployeeModel? getEmployeeById(String id) {
    for (final employee in _employees) {
      if (employee.id == id) return employee;
    }
    return null;
  }

  Future<void> _syncAttendanceToProductionCost(
    AttendanceRecord attendance,
    EmployeeModel employee,
  ) async {
    try {
      await _laborCostSync.sync(attendance: attendance, employee: employee);
    } catch (_) {
      // Keep attendance responsive if the cost ledger is temporarily unavailable.
    }
  }

  /// Đồng bộ lại toàn bộ chấm công sản xuất đã hoàn thành.
  /// Hữu ích cho dữ liệu cũ được tạo trước khi bật tự động đồng bộ.
  Future<int> syncProductionAttendanceCosts() async {
    var synced = 0;
    for (final attendance in _attendanceLogs) {
      if (attendance.fieldId == null ||
          attendance.fieldId!.isEmpty ||
          attendance.checkOut == null ||
          attendance.hours <= 0)
        continue;
      final employee = getEmployeeById(attendance.employeeId);
      if (employee == null) continue;
      final result = await _laborCostSync.sync(
        attendance: attendance,
        employee: employee,
      );
      if (result != null) synced++;
    }
    return synced;
  }

  PayrollRecord calculatePayroll(String employeeId, int month, int year) {
    final employee = _employees.firstWhere((e) => e.id == employeeId);
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
    return PayrollRecord(
      employeeId: employeeId,
      employeeName: employee.name,
      month: month,
      year: year,
      workingDays: workingDays,
      totalSalary: totalSalary,
      netSalary: totalSalary,
    );
  }

  void generatePayroll(int month, int year) {
    _payrollRecords.clear();
    for (var employee in _employees) {
      _payrollRecords.add(calculatePayroll(employee.id, month, year));
    }
    notifyListeners();
  }

  List<EmployeeModel> getEmployeesByDepartment(String department) =>
      _employees.where((e) => e.department == department).toList();

  List<AttendanceRecord> getAttendanceHistory(String employeeId) =>
      _attendanceLogs
          .where((record) => record.employeeId == employeeId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
}
