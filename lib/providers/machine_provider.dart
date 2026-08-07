import 'package:flutter/material.dart';
import '../models/machine_model.dart';
import '../models/field_model.dart';

class MachineProvider extends ChangeNotifier {
  List<MachineModel> _machines = [];

  List<MachineModel> get machines => _machines;

  MachineProvider() {
    _machines = [
      MachineModel(
        id: 'M001',
        name: 'Máy cày Yanmar',
        type: 'Máy cày',
        manufacturer: 'Yanmar',
        year: 2022,
        status: 'Tốt',
        totalHours: 350,
        fuelConsumption: 8.5,
        currentFieldId: 'LO0001', // Đang làm ở lô cà phê
      ),
      MachineModel(
        id: 'M002',
        name: 'Máy gặt Kubota',
        type: 'Máy gặt',
        manufacturer: 'Kubota',
        year: 2021,
        status: 'Đang bảo trì',
        totalHours: 520,
        fuelConsumption: 12.0,
        currentFieldId: null,
      ),
      MachineModel(
        id: 'M003',
        name: 'Xe tải Hino',
        type: 'Xe tải',
        manufacturer: 'Hino',
        year: 2023,
        status: 'Tốt',
        totalHours: 180,
        fuelConsumption: 15.5,
        currentFieldId: null,
      ),
      MachineModel(
        id: 'M004',
        name: 'Máy kéo John Deere',
        type: 'Máy kéo',
        manufacturer: 'John Deere',
        year: 2022,
        status: 'Tốt',
        totalHours: 420,
        fuelConsumption: 10.0,
        currentFieldId: 'LO0002', // Đang làm ở lô tiêu
      ),
    ];

    // Thêm lịch sử làm việc mẫu
    _machines[0].fieldHistory = [
      MachineFieldRecord(
        fieldId: 'LO0001',
        fieldName: 'Lô cà phê A1',
        startDate: DateTime(2024, 1, 10),
        endDate: DateTime(2024, 1, 15),
        hoursWorked: 40,
        fuelUsed: 320,
        operatorName: 'Nguyễn Văn An',
      ),
    ];
    _machines[3].fieldHistory = [
      MachineFieldRecord(
        fieldId: 'LO0002',
        fieldName: 'Lô tiêu B2',
        startDate: DateTime(2024, 1, 5),
        endDate: DateTime(2024, 1, 12),
        hoursWorked: 56,
        fuelUsed: 500,
        operatorName: 'Hoàng Văn Em',
      ),
    ];
  }

  // Lấy máy theo ID
  MachineModel? getMachineById(String id) {
    try {
      return _machines.firstWhere((m) => m.id == id);
    } catch (e) {
      return null;
    }
  }

  // Lấy danh sách máy đang làm việc trên một lô
  List<MachineModel> getMachinesByField(String fieldId) {
    return _machines.where((m) => m.currentFieldId == fieldId).toList();
  }

  // Lấy danh sách máy theo trạng thái
  List<MachineModel> getMachinesByStatus(String status) {
    return _machines.where((m) => m.status == status).toList();
  }

  // Gán máy vào lô đất (bắt đầu làm việc)
  void assignMachineToField(
    String machineId,
    String fieldId,
    String fieldName,
    String operatorName,
  ) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      // Cập nhật currentFieldId
      _machines[index] = _machines[index].copyWith(currentFieldId: fieldId);

      // Thêm vào lịch sử
      final newRecord = MachineFieldRecord(
        fieldId: fieldId,
        fieldName: fieldName,
        startDate: DateTime.now(),
        hoursWorked: 0,
        fuelUsed: 0,
        operatorName: operatorName,
      );

      final updatedHistory = List<MachineFieldRecord>.from(
        _machines[index].fieldHistory,
      )..add(newRecord);
      _machines[index] = _machines[index].copyWith(
        fieldHistory: updatedHistory,
      );

      notifyListeners();
    }
  }

  // Cập nhật tiến độ làm việc trên lô (cập nhật giờ và nhiên liệu)
  void updateFieldProgress(String machineId, double hours, double fuel) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      final history = _machines[index].fieldHistory;
      if (history.isNotEmpty) {
        final lastRecord = history.last;
        // Kiểm tra nếu bản ghi cuối cùng là đang làm việc (chưa có endDate)
        if (lastRecord.endDate == null) {
          // Cập nhật bản ghi cuối cùng
          final updatedRecord = MachineFieldRecord(
            fieldId: lastRecord.fieldId,
            fieldName: lastRecord.fieldName,
            startDate: lastRecord.startDate,
            endDate: lastRecord.endDate,
            hoursWorked: lastRecord.hoursWorked + hours,
            fuelUsed: lastRecord.fuelUsed + fuel,
            operatorName: lastRecord.operatorName,
          );

          final updatedHistory = List<MachineFieldRecord>.from(history)
            ..removeLast()
            ..add(updatedRecord);

          _machines[index] = _machines[index].copyWith(
            fieldHistory: updatedHistory,
            totalHours: _machines[index].totalHours + hours.toInt(),
          );
          notifyListeners();
        }
      }
    }
  }

  // Hoàn thành công việc trên lô (rời lô)
  void completeFieldWork(String machineId) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      final history = _machines[index].fieldHistory;
      if (history.isNotEmpty) {
        final lastRecord = history.last;
        if (lastRecord.endDate == null) {
          // Cập nhật endDate
          final updatedRecord = MachineFieldRecord(
            fieldId: lastRecord.fieldId,
            fieldName: lastRecord.fieldName,
            startDate: lastRecord.startDate,
            endDate: DateTime.now(),
            hoursWorked: lastRecord.hoursWorked,
            fuelUsed: lastRecord.fuelUsed,
            operatorName: lastRecord.operatorName,
          );

          final updatedHistory = List<MachineFieldRecord>.from(history)
            ..removeLast()
            ..add(updatedRecord);

          _machines[index] = _machines[index].copyWith(
            fieldHistory: updatedHistory,
            currentFieldId: null, // Không còn làm ở lô nào
          );
          notifyListeners();
        }
      }
    }
  }

  // Cập nhật trạng thái máy
  void updateMachineStatus(String id, String newStatus) {
    final index = _machines.indexWhere((m) => m.id == id);
    if (index != -1) {
      _machines[index] = _machines[index].copyWith(status: newStatus);
      notifyListeners();
    }
  }

  // Cập nhật giờ vận hành
  void updateMachineHours(String id, int hours) {
    final index = _machines.indexWhere((m) => m.id == id);
    if (index != -1) {
      final newTotal = _machines[index].totalHours + hours;
      _machines[index] = _machines[index].copyWith(totalHours: newTotal);
      notifyListeners();
    }
  }

  // Thêm máy mới
  void addMachine(MachineModel machine) {
    _machines.add(machine);
    notifyListeners();
  }

  // Xóa máy
  void removeMachine(String id) {
    _machines.removeWhere((m) => m.id == id);
    notifyListeners();
  }
}
