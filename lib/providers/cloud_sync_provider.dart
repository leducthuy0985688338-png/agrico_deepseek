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
import '../models/field_measurement_history.dart';
import '../models/production_season_model.dart';
import '../models/production_log_model.dart';
import '../models/harvest_record_model.dart';
import '../models/production_cost_model.dart';
import '../models/distance_measurement.dart';

class FuelRestoreData {
  final List<FuelModel> fuels;
  final List<FuelTransaction> transactions;

  const FuelRestoreData({
    required this.fuels,
    required this.transactions,
  });

  bool get isEmpty => fuels.isEmpty && transactions.isEmpty;
}

class WorkforceMachineRestoreData {
  final List<EmployeeModel> employees;
  final List<MachineModel> machines;

  const WorkforceMachineRestoreData({
    required this.employees,
    required this.machines,
  });

  bool get isEmpty => employees.isEmpty && machines.isEmpty;
}

class CloudRestoreData {
  final List<FieldModel> fields;
  final List<FieldMeasurementHistory> fieldMeasurements;
  final List<ProductionSeasonModel> seasons;
  final List<ProductionLogModel> productionLogs;
  final List<HarvestRecordModel> harvestRecords;
  final List<ProductionCostModel> productionCosts;
  final List<EmployeeModel> employees;
  final List<MachineModel> machines;
  final List<TaskModel> tasks;
  final List<DistanceMeasurement> distanceMeasurements;
  final List<WarehouseItem> warehouseItems;
  final List<FuelModel> fuels;
  final List<FuelTransaction> fuelTransactions;
  final List<FinanceRecord> financeRecords;

  const CloudRestoreData({
    required this.fields,
    required this.fieldMeasurements,
    required this.seasons,
    required this.productionLogs,
    required this.harvestRecords,
    required this.productionCosts,
    required this.employees,
    required this.machines,
    required this.tasks,
    required this.distanceMeasurements,
    required this.warehouseItems,
    required this.fuels,
    required this.fuelTransactions,
    required this.financeRecords,
  });

  bool get isEmpty =>
      fields.isEmpty &&
      fieldMeasurements.isEmpty &&
      seasons.isEmpty &&
      productionLogs.isEmpty &&
      harvestRecords.isEmpty &&
      productionCosts.isEmpty &&
      employees.isEmpty &&
      machines.isEmpty &&
      tasks.isEmpty &&
      distanceMeasurements.isEmpty &&
      warehouseItems.isEmpty &&
      fuels.isEmpty &&
      fuelTransactions.isEmpty &&
      financeRecords.isEmpty;
}

class CloudSyncProvider extends ChangeNotifier {
  bool _isSyncing = false;
  bool _isRestoringAll = false;
  bool _isRestoringFuel = false;
  bool _isRestoringFinance = false;
  bool _isRestoringFields = false;
  bool _isRestoringFieldMeasurements = false;
  bool _isRestoringSeasons = false;
  bool _isRestoringProductionLogs = false;
  bool _isRestoringHarvestRecords = false;
  bool _isRestoringProductionCosts = false;
  bool _isRestoringWorkforceMachines = false;
  bool _isRestoringWarehouse = false;
  bool _isRestoringTasks = false;
  bool _isRestoringDistanceMeasurements = false;
  int _restoreAllCompletedSteps = 0;
  String _restoreAllStep = '';
  String? _lastSyncTime;
  bool _isConnected = false;

  bool get isSyncing => _isSyncing;
  bool get isRestoringAll => _isRestoringAll;
  bool get isRestoringFuel => _isRestoringFuel;
  bool get isRestoringFinance => _isRestoringFinance;
  bool get isRestoringFields => _isRestoringFields;
  bool get isRestoringFieldMeasurements => _isRestoringFieldMeasurements;
  bool get isRestoringSeasons => _isRestoringSeasons;
  bool get isRestoringProductionLogs => _isRestoringProductionLogs;
  bool get isRestoringHarvestRecords => _isRestoringHarvestRecords;
  bool get isRestoringProductionCosts => _isRestoringProductionCosts;
  bool get isRestoringWorkforceMachines => _isRestoringWorkforceMachines;
  bool get isRestoringWarehouse => _isRestoringWarehouse;
  bool get isRestoringTasks => _isRestoringTasks;
  bool get isRestoringDistanceMeasurements =>
      _isRestoringDistanceMeasurements;
  int get restoreAllCompletedSteps => _restoreAllCompletedSteps;
  int get restoreAllTotalSteps => 12;
  String get restoreAllStep => _restoreAllStep;
  double get restoreAllProgress =>
      _restoreAllCompletedSteps / restoreAllTotalSteps;
  bool get isBusy =>
      _isSyncing ||
      _isRestoringAll ||
      _isRestoringFuel ||
      _isRestoringFinance ||
      _isRestoringFields ||
      _isRestoringFieldMeasurements ||
      _isRestoringSeasons ||
      _isRestoringProductionLogs ||
      _isRestoringHarvestRecords ||
      _isRestoringProductionCosts ||
      _isRestoringWorkforceMachines ||
      _isRestoringWarehouse ||
      _isRestoringTasks ||
      _isRestoringDistanceMeasurements;
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
    required List<FuelTransaction> fuelTransactions,
    required List<FieldModel> fields,
    required List<FieldMeasurementHistory> fieldMeasurements,
    required List<ProductionSeasonModel> seasons,
    required List<ProductionLogModel> productionLogs,
    required List<HarvestRecordModel> harvestRecords,
    required List<ProductionCostModel> productionCosts,
  }) async {
    if (isBusy) return false;

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
        fuelTransactions: fuelTransactions,
        fields: fields,
        seasons: seasons,
        productionLogs: productionLogs,
        harvestRecords: harvestRecords,
        productionCosts: productionCosts,
      );
      await CloudService.syncFieldMeasurements(fieldMeasurements);

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

  Future<T> restoreAllData<T>({
    required Future<T> Function(CloudRestoreData data) apply,
  }) async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringAll = true;
    _restoreAllCompletedSteps = 0;
    _restoreAllStep = 'Đang chuẩn bị';
    notifyListeners();

    try {
      final fields = await _loadRestoreStep(
        step: 'Lô đất',
        loader: CloudService.loadFields,
      );
      final fieldMeasurements = await _loadRestoreStep(
        step: 'Lịch sử đo diện tích',
        loader: CloudService.loadFieldMeasurements,
      );
      final seasons = await _loadRestoreStep(
        step: 'Mùa vụ',
        loader: CloudService.loadProductionSeasons,
      );
      final productionLogs = await _loadRestoreStep(
        step: 'Nhật ký sản xuất',
        loader: CloudService.loadProductionLogs,
      );
      final harvestRecords = await _loadRestoreStep(
        step: 'Thu hoạch',
        loader: CloudService.loadHarvestRecords,
      );

      _setRestoreAllStep('Nhân sự và máy móc');
      final employees = await CloudService.loadEmployees();
      final machines = await CloudService.loadMachines();
      _completeRestoreAllStep();

      final tasks = await _loadRestoreStep(
        step: 'Công việc và lịch việc',
        loader: CloudService.loadTasks,
      );
      final distanceMeasurements = await _loadRestoreStep(
        step: 'Lịch sử đo khoảng cách',
        loader: CloudService.loadDistanceMeasurements,
      );
      final warehouseItems = await _loadRestoreStep(
        step: 'Kho vật tư',
        loader: CloudService.loadWarehouseItems,
      );
      final productionCosts = await _loadRestoreStep(
        step: 'Chi phí sản xuất',
        loader: CloudService.loadProductionCosts,
      );

      _setRestoreAllStep('Nhiên liệu');
      final fuels = await CloudService.loadFuels();
      final fuelTransactions = await CloudService.loadFuelTransactions();
      _completeRestoreAllStep();

      final financeRecords = await _loadRestoreStep(
        step: 'Tài chính',
        loader: CloudService.loadFinanceRecords,
      );

      final data = CloudRestoreData(
        fields: fields,
        fieldMeasurements: fieldMeasurements,
        seasons: seasons,
        productionLogs: productionLogs,
        harvestRecords: harvestRecords,
        productionCosts: productionCosts,
        employees: employees,
        machines: machines,
        tasks: tasks,
        distanceMeasurements: distanceMeasurements,
        warehouseItems: warehouseItems,
        fuels: fuels,
        fuelTransactions: fuelTransactions,
        financeRecords: financeRecords,
      );
      _isConnected = true;
      _setRestoreAllStep('Áp dụng dữ liệu trên thiết bị');
      return await apply(data);
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringAll = false;
      notifyListeners();
    }
  }

  Future<T> _loadRestoreStep<T>({
    required String step,
    required Future<T> Function() loader,
  }) async {
    _setRestoreAllStep(step);
    final result = await loader();
    _completeRestoreAllStep();
    return result;
  }

  void _setRestoreAllStep(String step) {
    _restoreAllStep = step;
    notifyListeners();
  }

  void _completeRestoreAllStep() {
    _restoreAllCompletedSteps++;
    notifyListeners();
  }

  Future<FuelRestoreData> restoreFuelData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringFuel = true;
    notifyListeners();

    try {
      final fuels = await CloudService.loadFuels();
      final transactions = await CloudService.loadFuelTransactions();
      _isConnected = true;
      return FuelRestoreData(fuels: fuels, transactions: transactions);
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringFuel = false;
      notifyListeners();
    }
  }

  Future<List<FinanceRecord>> restoreFinanceData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringFinance = true;
    notifyListeners();

    try {
      final records = await CloudService.loadFinanceRecords();
      _isConnected = true;
      return records;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringFinance = false;
      notifyListeners();
    }
  }

  Future<List<FieldModel>> restoreFieldData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringFields = true;
    notifyListeners();

    try {
      final fields = await CloudService.loadFields();
      _isConnected = true;
      return fields;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringFields = false;
      notifyListeners();
    }
  }

  Future<List<FieldMeasurementHistory>>
      restoreFieldMeasurementData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringFieldMeasurements = true;
    notifyListeners();

    try {
      final measurements = await CloudService.loadFieldMeasurements();
      _isConnected = true;
      return measurements;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringFieldMeasurements = false;
      notifyListeners();
    }
  }

  Future<List<ProductionSeasonModel>> restoreSeasonData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringSeasons = true;
    notifyListeners();

    try {
      final seasons = await CloudService.loadProductionSeasons();
      _isConnected = true;
      return seasons;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringSeasons = false;
      notifyListeners();
    }
  }

  Future<List<ProductionLogModel>> restoreProductionLogData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringProductionLogs = true;
    notifyListeners();

    try {
      final logs = await CloudService.loadProductionLogs();
      _isConnected = true;
      return logs;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringProductionLogs = false;
      notifyListeners();
    }
  }

  Future<List<HarvestRecordModel>> restoreHarvestData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringHarvestRecords = true;
    notifyListeners();

    try {
      final records = await CloudService.loadHarvestRecords();
      _isConnected = true;
      return records;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringHarvestRecords = false;
      notifyListeners();
    }
  }

  Future<List<ProductionCostModel>> restoreProductionCostData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringProductionCosts = true;
    notifyListeners();

    try {
      final records = await CloudService.loadProductionCosts();
      _isConnected = true;
      return records;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringProductionCosts = false;
      notifyListeners();
    }
  }

  Future<WorkforceMachineRestoreData>
      restoreWorkforceMachineData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringWorkforceMachines = true;
    notifyListeners();

    try {
      final employees = await CloudService.loadEmployees();
      final machines = await CloudService.loadMachines();
      _isConnected = true;
      return WorkforceMachineRestoreData(
        employees: employees,
        machines: machines,
      );
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringWorkforceMachines = false;
      notifyListeners();
    }
  }

  Future<List<WarehouseItem>> restoreWarehouseData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringWarehouse = true;
    notifyListeners();

    try {
      final items = await CloudService.loadWarehouseItems();
      _isConnected = true;
      return items;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringWarehouse = false;
      notifyListeners();
    }
  }

  Future<List<TaskModel>> restoreTaskData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringTasks = true;
    notifyListeners();

    try {
      final tasks = await CloudService.loadTasks();
      _isConnected = true;
      return tasks;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringTasks = false;
      notifyListeners();
    }
  }

  Future<List<DistanceMeasurement>>
      restoreDistanceMeasurementData() async {
    if (isBusy) {
      throw StateError('Đang có thao tác Cloud khác, vui lòng chờ hoàn tất.');
    }

    _isRestoringDistanceMeasurements = true;
    notifyListeners();

    try {
      final measurements = await CloudService.loadDistanceMeasurements();
      _isConnected = true;
      return measurements;
    } catch (_) {
      _isConnected = false;
      rethrow;
    } finally {
      _isRestoringDistanceMeasurements = false;
      notifyListeners();
    }
  }

  // ====== LẤY DỮ LIỆU TỪ CLOUD ======
  Stream<List<WarehouseItem>> getWarehouseItems() {
    return CloudService.getWarehouseItems().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data =
            Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
        data['id'] ??= doc.id;
        return WarehouseItem.fromMap(data);
      }).toList(growable: false);
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
      final tasks = <TaskModel>[];
      for (final doc in snapshot.docs) {
        final data =
            Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
        data['id'] ??= doc.id;
        for (final key in [
          'dueDate',
          'completedDate',
          'createdAt',
          'updatedAt',
        ]) {
          final value = data[key];
          if (value is Timestamp) {
            data[key] = value.toDate().toUtc().toIso8601String();
          } else if (value is DateTime) {
            data[key] = value.toUtc().toIso8601String();
          }
        }

        try {
          tasks.add(TaskModel.fromMap(data));
        } on FormatException {
          // Bỏ qua tài liệu Cloud không đủ dữ liệu bắt buộc.
        }
      }
      return tasks;
    });
  }
}
