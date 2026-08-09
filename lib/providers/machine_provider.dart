import 'package:flutter/material.dart';
import '../models/machine_model.dart';
import '../models/field_model.dart';
import '../services/machine_production_cost_sync_service.dart';

class MachineProvider extends ChangeNotifier {
  List<MachineModel> _machines = [];
  final MachineProductionCostSyncService _productionCostSync = MachineProductionCostSyncService();

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
        costPerHour: 0,
        currentFieldId: 'LO0001',
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
        costPerHour: 0,
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
        costPerHour: 0,
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
        costPerHour: 0,
        currentFieldId: 'LO0002',
      ),
    ];

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

  MachineModel? getMachineById(String id) {
    try {
      return _machines.firstWhere((m) => m.id == id);
    } catch (e) {
      return null;
    }
  }

  List<MachineModel> getMachinesByField(String fieldId) {
    return _machines.where((m) => m.currentFieldId == fieldId).toList();
  }

  List<MachineModel> getMachinesByStatus(String status) {
    return _machines.where((m) => m.status == status).toList();
  }

  void assignMachineToField(
    String machineId,
    String fieldId,
    String fieldName,
    String operatorName,
  ) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      _machines[index] = _machines[index].copyWith(currentFieldId: fieldId);

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

  /// Cập nhật giờ vận hành trên lô và đồng bộ chi phí máy.
  ///
  /// Chi phí chỉ được ghi khi máy đã cấu hình `costPerHour > 0`. Nhiên liệu
  /// vẫn là nguồn chi phí riêng, không cộng lại vào chi phí máy.
  void updateFieldProgress(String machineId, double hours, double fuel) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      final history = _machines[index].fieldHistory;
      if (history.isNotEmpty) {
        final lastRecord = history.last;
        if (lastRecord.endDate == null) {
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

          final updatedMachine = _machines[index].copyWith(
            fieldHistory: updatedHistory,
            totalHours: _machines[index].totalHours + hours.toInt(),
          );
          _machines[index] = updatedMachine;

          _syncProductionCost(updatedMachine, updatedRecord);
          notifyListeners();
        }
      }
    }
  }

  Future<void> _syncProductionCost(
    MachineModel machine,
    MachineFieldRecord work,
  ) async {
    try {
      await _productionCostSync.sync(
        machine: machine,
        work: work,
        costPerHour: machine.costPerHour,
      );
    } catch (_) {
      // Không để lỗi ledger làm hỏng nhật ký máy.
    }
  }

  /// Cấu hình đơn giá vận hành/khấu hao theo giờ cho máy.
  void updateMachineCostPerHour(String id, double costPerHour) {
    if (costPerHour < 0) return;
    final index = _machines.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _machines[index] = _machines[index].copyWith(costPerHour: costPerHour);
    notifyListeners();
  }

  /// Đồng bộ lại toàn bộ lịch sử làm việc của một máy sau khi đã cấu hình
  /// đơn giá giờ. Các bản ghi đã có sẽ được upsert, không tạo bản sao.
  Future<void> syncMachineProductionCosts(String machineId) async {
    final machine = getMachineById(machineId);
    if (machine == null || machine.costPerHour <= 0) return;
    for (final work in machine.fieldHistory) {
      await _productionCostSync.sync(
        machine: machine,
        work: work,
        costPerHour: machine.costPerHour,
      );
    }
  }

  void completeFieldWork(String machineId) {
    final index = _machines.indexWhere((m) => m.id == machineId);
    if (index != -1) {
      final history = _machines[index].fieldHistory;
      if (history.isNotEmpty) {
        final lastRecord = history.last;
        if (lastRecord.endDate == null) {
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

          final updatedMachine = _machines[index].copyWith(
            fieldHistory: updatedHistory,
            currentFieldId: null,
          );
          _machines[index] = updatedMachine;
          _syncProductionCost(updatedMachine, updatedRecord);
          notifyListeners();
        }
      }
    }
  }

  void updateMachineStatus(String id, String newStatus) {
    final index = _machines.indexWhere((m) => m.id == id);
    if (index != -1) {
      _machines[index] = _machines[index].copyWith(status: newStatus);
      notifyListeners();
    }
  }

  void updateMachineHours(String id, int hours) {
    final index = _machines.indexWhere((m) => m.id == id);
    if (index != -1) {
      final newTotal = _machines[index].totalHours + hours;
      _machines[index] = _machines[index].copyWith(totalHours: newTotal);
      notifyListeners();
    }
  }

  void addMachine(MachineModel machine) {
    _machines.add(machine);
    notifyListeners();
  }

  void removeMachine(String id) {
    _machines.removeWhere((m) => m.id == id);
    notifyListeners();
  }
}
