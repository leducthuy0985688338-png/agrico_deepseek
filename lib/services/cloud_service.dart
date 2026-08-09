import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/warehouse_item.dart';
import '../models/machine_model.dart';
import '../models/employee_model.dart';
import '../models/task_model.dart';
import '../models/finance_model.dart';
import '../models/fuel_model.dart';

class CloudService {
  static FirebaseFirestore? _firestore;
  static bool _isInitialized = false;

  // ====== KHỞI TẠO FIREBASE ======
  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      // Kiểm tra nếu đã khởi tạo thì bỏ qua
      if (Firebase.apps.isNotEmpty) {
        _firestore = FirebaseFirestore.instance;
        _isInitialized = true;
        print('✅ Firebase already initialized');
        return;
      }

      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      _isInitialized = true;
      print('✅ Firebase initialized successfully');
    } catch (e) {
      print('❌ Firebase initialization failed: $e');
      // Không rethrow để app vẫn chạy nếu không có Firebase
    }
  }

  static FirebaseFirestore get db {
    if (!_isInitialized || _firestore == null) {
      throw Exception(
        'Firebase chưa được khởi tạo. Gọi CloudService.initialize() trước.',
      );
    }
    return _firestore!;
  }

  // ============================================================
  // ====== VẬT TƯ (WAREHOUSE) ======
  // ============================================================
  static Future<void> saveWarehouseItem(WarehouseItem item) async {
    try {
      await db.collection('warehouse').doc(item.id).set({
        'id': item.id,
        'name': item.name,
        'unit': item.unit,
        'importPrice': item.importPrice,
        'supplier': item.supplier,
        'stock': item.stock,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Saved warehouse item: ${item.id}');
    } catch (e) {
      print('❌ Error saving warehouse item: $e');
      rethrow;
    }
  }

  static Stream<QuerySnapshot> getWarehouseItems() {
    return db.collection('warehouse').orderBy('name').snapshots();
  }

  static Future<void> deleteWarehouseItem(String id) async {
    try {
      await db.collection('warehouse').doc(id).delete();
      print('✅ Deleted warehouse item: $id');
    } catch (e) {
      print('❌ Error deleting warehouse item: $e');
      rethrow;
    }
  }

  // ============================================================
  // ====== MÁY MÓC (MACHINE) ======
  // ============================================================
  static Future<void> saveMachine(MachineModel machine) async {
    try {
      await db.collection('machines').doc(machine.id).set({
        'id': machine.id,
        'name': machine.name,
        'type': machine.type,
        'manufacturer': machine.manufacturer,
        'year': machine.year,
        'status': machine.status,
        'totalHours': machine.totalHours,
        'fuelConsumption': machine.fuelConsumption,
        'currentFieldId': machine.currentFieldId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Saved machine: ${machine.id}');
    } catch (e) {
      print('❌ Error saving machine: $e');
      rethrow;
    }
  }

  static Stream<QuerySnapshot> getMachines() {
    return db.collection('machines').orderBy('name').snapshots();
  }

  static Future<void> deleteMachine(String id) async {
    try {
      await db.collection('machines').doc(id).delete();
      print('✅ Deleted machine: $id');
    } catch (e) {
      print('❌ Error deleting machine: $e');
      rethrow;
    }
  }

  // ============================================================
  // ====== NHÂN VIÊN (EMPLOYEE) ======
  // ============================================================
  static Future<void> saveEmployee(EmployeeModel employee) async {
    try {
      await db.collection('employees').doc(employee.id).set({
        'id': employee.id,
        'name': employee.name,
        'position': employee.position,
        'department': employee.department,
        'dailyRate': employee.dailyRate,
        'phone': employee.phone,
        'address': employee.address,
        'isActive': employee.isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Saved employee: ${employee.id}');
    } catch (e) {
      print('❌ Error saving employee: $e');
      rethrow;
    }
  }

  static Stream<QuerySnapshot> getEmployees() {
    return db.collection('employees').orderBy('name').snapshots();
  }

  static Future<void> deleteEmployee(String id) async {
    try {
      await db.collection('employees').doc(id).delete();
      print('✅ Deleted employee: $id');
    } catch (e) {
      print('❌ Error deleting employee: $e');
      rethrow;
    }
  }

  // ============================================================
  // ====== CÔNG VIỆC (TASK) ======
  // ============================================================
  static Future<void> saveTask(TaskModel task) async {
    try {
      await db.collection('tasks').doc(task.id).set({
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'priority': task.priority.index,
        'status': task.status.index,
        'dueDate': task.dueDate.toIso8601String(),
        'completedDate': task.completedDate?.toIso8601String(),
        'assignedTo': task.assignedTo,
        'assignedToName': task.assignedToName,
        'fieldId': task.fieldId,
        'fieldName': task.fieldName,
        'machineId': task.machineId,
        'machineName': task.machineName,
        'tags': task.tags,
        'createdAt': task.createdAt.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Saved task: ${task.id}');
    } catch (e) {
      print('❌ Error saving task: $e');
      rethrow;
    }
  }

  static Stream<QuerySnapshot> getTasks() {
    return db.collection('tasks').orderBy('dueDate').snapshots();
  }

  static Future<void> deleteTask(String id) async {
    try {
      await db.collection('tasks').doc(id).delete();
      print('✅ Deleted task: $id');
    } catch (e) {
      print('❌ Error deleting task: $e');
      rethrow;
    }
  }

  // ============================================================
  // ====== GIAO DỊCH TÀI CHÍNH (FINANCE) ======
  // ============================================================
  static Future<void> saveFinanceRecord(FinanceRecord record) async {
    try {
      await db.collection('finance').doc(record.id).set({
        'id': record.id,
        'fieldId': record.fieldId,
        'fieldName': record.fieldName,
        'date': record.date.toIso8601String(),
        'type': record.type.index,
        'category': record.category,
        'amount': record.amount,
        'description': record.description,
        'machineId': record.machineId,
        'machineName': record.machineName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Saved finance record: ${record.id}');
    } catch (e) {
      print('❌ Error saving finance record: $e');
      rethrow;
    }
  }

  static Stream<QuerySnapshot> getFinanceRecords() {
    return db
        .collection('finance')
        .orderBy('date', descending: true)
        .snapshots();
  }

  static Future<void> deleteFinanceRecord(String id) async {
    try {
      await db.collection('finance').doc(id).delete();
      print('✅ Deleted finance record: $id');
    } catch (e) {
      print('❌ Error deleting finance record: $e');
      rethrow;
    }
  }

  // ============================================================
  // ====== NHIÊN LIỆU (FUEL) ======
  // ============================================================
  static Future<void> saveFuel(FuelModel fuel) async {
    try {
      await db.collection('fuel').doc(fuel.id).set({
        'id': fuel.id,
        'name': fuel.name,
        'unit': fuel.unit,
        'stock': fuel.stock,
        'unitPrice': fuel.unitPrice,
        'supplier': fuel.supplier,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Saved fuel: ${fuel.id}');
    } catch (e) {
      print('❌ Error saving fuel: $e');
      rethrow;
    }
  }

  static Stream<QuerySnapshot> getFuels() {
    return db.collection('fuel').orderBy('name').snapshots();
  }

  static Future<void> deleteFuel(String id) async {
    try {
      await db.collection('fuel').doc(id).delete();
      print('✅ Deleted fuel: $id');
    } catch (e) {
      print('❌ Error deleting fuel: $e');
      rethrow;
    }
  }

  // ============================================================
  // ====== ĐỒNG BỘ DỮ LIỆU (SYNC) ======
  // ============================================================
  static Future<void> syncAllData({
    required List<WarehouseItem> warehouseItems,
    required List<MachineModel> machines,
    required List<EmployeeModel> employees,
    required List<TaskModel> tasks,
    required List<FinanceRecord> financeRecords,
    required List<FuelModel> fuels,
  }) async {
    try {
      // Lưu tất cả dữ liệu lên Cloud
      final batch = db.batch();

      for (var item in warehouseItems) {
        final ref = db.collection('warehouse').doc(item.id);
        batch.set(ref, {
          'id': item.id,
          'name': item.name,
          'unit': item.unit,
          'importPrice': item.importPrice,
          'supplier': item.supplier,
          'stock': item.stock,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      for (var machine in machines) {
        final ref = db.collection('machines').doc(machine.id);
        batch.set(ref, {
          'id': machine.id,
          'name': machine.name,
          'type': machine.type,
          'manufacturer': machine.manufacturer,
          'year': machine.year,
          'status': machine.status,
          'totalHours': machine.totalHours,
          'fuelConsumption': machine.fuelConsumption,
          'currentFieldId': machine.currentFieldId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      for (var employee in employees) {
        final ref = db.collection('employees').doc(employee.id);
        batch.set(ref, {
          'id': employee.id,
          'name': employee.name,
          'position': employee.position,
          'department': employee.department,
          'dailyRate': employee.dailyRate,
          'phone': employee.phone,
          'address': employee.address,
          'isActive': employee.isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      for (var task in tasks) {
        final ref = db.collection('tasks').doc(task.id);
        batch.set(ref, {
          'id': task.id,
          'title': task.title,
          'description': task.description,
          'priority': task.priority.index,
          'status': task.status.index,
          'dueDate': task.dueDate.toIso8601String(),
          'completedDate': task.completedDate?.toIso8601String(),
          'assignedTo': task.assignedTo,
          'assignedToName': task.assignedToName,
          'fieldId': task.fieldId,
          'fieldName': task.fieldName,
          'machineId': task.machineId,
          'machineName': task.machineName,
          'tags': task.tags,
          'createdAt': task.createdAt.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      for (var record in financeRecords) {
        final ref = db.collection('finance').doc(record.id);
        batch.set(ref, {
          'id': record.id,
          'fieldId': record.fieldId,
          'fieldName': record.fieldName,
          'date': record.date.toIso8601String(),
          'type': record.type.index,
          'category': record.category,
          'amount': record.amount,
          'description': record.description,
          'machineId': record.machineId,
          'machineName': record.machineName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      for (var fuel in fuels) {
        final ref = db.collection('fuel').doc(fuel.id);
        batch.set(ref, {
          'id': fuel.id,
          'name': fuel.name,
          'unit': fuel.unit,
          'stock': fuel.stock,
          'unitPrice': fuel.unitPrice,
          'supplier': fuel.supplier,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print('✅ All data synced successfully!');
    } catch (e) {
      print('❌ Error syncing data: $e');
      rethrow;
    }
  }

  // ============================================================
  // ====== KIỂM TRA KẾT NỐI ======
  // ============================================================
  static Future<bool> checkConnection() async {
    try {
      await db.collection('_test').doc('test').set({'test': true});
      await db.collection('_test').doc('test').delete();
      return true;
    } catch (e) {
      print('❌ Connection check failed: $e');
      return false;
    }
  }
}
