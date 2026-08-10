import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/cloud_service.dart';
import '../models/warehouse_item.dart';
import '../models/machine_model.dart';
import '../models/employee_model.dart';
import '../models/task_model.dart';
import '../models/finance_model.dart';
import '../models/fuel_model.dart';
import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../models/production_log_model.dart';
import '../models/harvest_record_model.dart';

class CloudSyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  String? _lastSyncTime;
  bool _isConnected = false;

  bool get isSyncing => _isSyncing;
  String? get lastSyncTime => _lastSyncTime;
  bool get isConnected => _isConnected;

  // ====== KIỂM TRA KẾT NỐI ======
  Future<bool> checkConnection() async {
    _isConnected = await CloudService.checkConnection();
    notifyListeners();
    return _isConnected;
  }

  // ====== ĐỒNG BỘ DỮ LIỆU ======
  Future<bool> syncAllData({
    required List<WarehouseItem> warehouseItems,
    required List<MachineModel> machines,
    required List<EmployeeModel> employees,
    required List<TaskModel> tasks,
    required List<FinanceRecord> financeRecords,
    required List<FuelModel> fuels,
    required List<FieldModel> fields,
    required List<ProductionSeasonModel> seasons,
    required List<ProductionLogModel> productionLogs,
    required List<HarvestRecordModel> harvestRecords,
  }) async {
    if (_isSyncing) return false;

    _isSyncing = true;
    notifyListeners();

    try {
      await CloudService.syncAllData(
        warehouseItems: warehouseItems,
        machines: machines,
        employees: employees,
        tasks: tasks,
        financeRecords: financeRecords,
        fuels: fuels,
        fields: fields,
        seasons: seasons,
        productionLogs: productionLogs,
        harvestRecords: harvestRecords,
      );

      _lastSyncTime = DateTime.now().toString();
      _isConnected = true;
      _isSyncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isConnected = false;
      _isSyncing = false;
      notifyListeners();
      rethrow;
    }
  }

  // ====== LẤY DỮ LIỆU TỪ CLOUD ======
  Stream<List<WarehouseItem>> getWarehouseItems() {
    return CloudService.getWarehouseItems().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return WarehouseItem(
          id: data['id'],
          name: data['name'],
          unit: data['unit'],
          importPrice: data['importPrice'].toDouble(),
          supplier: data['supplier'],
          stock: data['stock'],
        );
      }).toList();
    });
  }

  Stream<List<MachineModel>> getMachines() {
    return CloudService.getMachines().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return MachineModel(
          id: data['id'],
          name: data['name'],
          type: data['type'],
          manufacturer: data['manufacturer'],
          year: data['year'],
          status: data['status'],
          totalHours: data['totalHours'],
          fuelConsumption: data['fuelConsumption'].toDouble(),
          currentFieldId: data['currentFieldId'],
        );
      }).toList();
    });
  }

  Stream<List<EmployeeModel>> getEmployees() {
    return CloudService.getEmployees().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return EmployeeModel(
          id: data['id'],
          name: data['name'],
          position: data['position'],
          department: data['department'],
          dailyRate: data['dailyRate'].toDouble(),
          phone: data['phone'],
          address: data['address'],
          isActive: data['isActive'],
        );
      }).toList();
    });
  }

  Stream<List<TaskModel>> getTasks() {
    return CloudService.getTasks().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return TaskModel(
          id: data['id'],
          title: data['title'],
          description: data['description'],
          priority: TaskPriority.values[data['priority']],
          status: TaskStatus.values[data['status']],
          dueDate: DateTime.parse(data['dueDate']),
          completedDate: data['completedDate'] != null
              ? DateTime.parse(data['completedDate'])
              : null,
          assignedTo: data['assignedTo'],
          assignedToName: data['assignedToName'],
          fieldId: data['fieldId'],
          fieldName: data['fieldName'],
          machineId: data['machineId'],
          machineName: data['machineName'],
          tags: List<String>.from(data['tags'] ?? []),
          createdAt: DateTime.parse(data['createdAt']),
          updatedAt: data['updatedAt'] != null
              ? (data['updatedAt'] as Timestamp).toDate()
              : null,
        );
      }).toList();
    });
  }
}
