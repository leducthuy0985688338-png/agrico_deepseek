import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/warehouse_item.dart';
import '../models/machine_model.dart';
import '../models/employee_model.dart';
import '../models/task_model.dart';
import '../models/finance_model.dart';
import '../models/fuel_model.dart';
import '../models/field_model.dart';
import '../models/distance_measurement_model.dart';

class CloudService {
  static FirebaseFirestore? _firestore;
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
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
    }
  }

  static FirebaseFirestore get db {
    if (!_isInitialized || _firestore == null) {
      throw Exception('Firebase chưa được khởi tạo. Gọi CloudService.initialize() trước.');
    }
    return _firestore!;
  }

  static Future<void> saveField(FieldModel field) async {
    await db.collection('fields').doc(field.id).set({
      'id': field.id,
      'name': field.name,
      'area': field.area,
      'crop': field.crop,
      'status': field.status,
      'perimeter': field.perimeter,
      'measurementMethod': field.measurementMethod,
      'gpsAccuracy': field.gpsAccuracy,
      'measuredAt': field.measuredAt == null ? null : Timestamp.fromDate(field.measuredAt!.toUtc()),
      'polygon': field.polygon.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(growable: false),
      'photoPaths': field.photoPaths,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getFields() =>
      db.collection('fields').orderBy('name').snapshots();

  static Future<void> deleteField(String id) => db.collection('fields').doc(id).delete();

  static Future<void> saveDistanceMeasurement(DistanceMeasurementModel measurement) async {
    await db.collection('distance_measurements').doc(measurement.id).set({
      'id': measurement.id,
      'start': {'lat': measurement.start.latitude, 'lng': measurement.start.longitude},
      'end': {'lat': measurement.end.latitude, 'lng': measurement.end.longitude},
      'distanceMeters': measurement.distanceMeters,
      'method': measurement.method,
      'measuredAt': Timestamp.fromDate(measurement.measuredAt.toUtc()),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getDistanceMeasurements() =>
      db.collection('distance_measurements').orderBy('measuredAt', descending: true).snapshots();

  static Future<void> deleteDistanceMeasurement(String id) =>
      db.collection('distance_measurements').doc(id).delete();

  // ====== VẬT TƯ ======
  static Future<void> saveWarehouseItem(WarehouseItem item) async {
    try {
      await db.collection('warehouse').doc(item.id).set({'id': item.id, 'name': item.name, 'unit': item.unit, 'importPrice': item.importPrice, 'supplier': item.supplier, 'stock': item.stock, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) { rethrow; }
  }
  static Stream<QuerySnapshot> getWarehouseItems() => db.collection('warehouse').orderBy('name').snapshots();
  static Future<void> deleteWarehouseItem(String id) => db.collection('warehouse').doc(id).delete();

  // ====== MÁY MÓC ======
  static Future<void> saveMachine(MachineModel machine) async {
    await db.collection('machines').doc(machine.id).set({'id': machine.id, 'name': machine.name, 'type': machine.type, 'manufacturer': machine.manufacturer, 'year': machine.year, 'status': machine.status, 'totalHours': machine.totalHours, 'fuelConsumption': machine.fuelConsumption, 'currentFieldId': machine.currentFieldId, 'updatedAt': FieldValue.serverTimestamp()});
  }
  static Stream<QuerySnapshot> getMachines() => db.collection('machines').orderBy('name').snapshots();
  static Future<void> deleteMachine(String id) => db.collection('machines').doc(id).delete();

  // ====== NHÂN VIÊN ======
  static Future<void> saveEmployee(EmployeeModel employee) async {
    await db.collection('employees').doc(employee.id).set({'id': employee.id, 'name': employee.name, 'position': employee.position, 'department': employee.department, 'dailyRate': employee.dailyRate, 'phone': employee.phone, 'address': employee.address, 'isActive': employee.isActive, 'updatedAt': FieldValue.serverTimestamp()});
  }
  static Stream<QuerySnapshot> getEmployees() => db.collection('employees').orderBy('name').snapshots();
  static Future<void> deleteEmployee(String id) => db.collection('employees').doc(id).delete();

  // ====== CÔNG VIỆC ======
  static Future<void> saveTask(TaskModel task) async {
    await db.collection('tasks').doc(task.id).set({'id': task.id, 'title': task.title, 'description': task.description, 'priority': task.priority.index, 'status': task.status.index, 'dueDate': task.dueDate.toIso8601String(), 'completedDate': task.completedDate?.toIso8601String(), 'assignedTo': task.assignedTo, 'assignedToName': task.assignedToName, 'fieldId': task.fieldId, 'fieldName': task.fieldName, 'machineId': task.machineId, 'machineName': task.machineName, 'tags': task.tags, 'createdAt': task.createdAt.toIso8601String(), 'updatedAt': FieldValue.serverTimestamp()});
  }
  static Stream<QuerySnapshot> getTasks() => db.collection('tasks').orderBy('dueDate').snapshots();
  static Future<void> deleteTask(String id) => db.collection('tasks').doc(id).delete();

  // ====== TÀI CHÍNH ======
  static Future<void> saveFinanceRecord(FinanceRecord record) async {
    await db.collection('finance').doc(record.id).set({'id': record.id, 'fieldId': record.fieldId, 'fieldName': record.fieldName, 'date': record.date.toIso8601String(), 'type': record.type.index, 'category': record.category, 'amount': record.amount, 'description': record.description, 'machineId': record.machineId, 'machineName': record.machineName, 'updatedAt': FieldValue.serverTimestamp()});
  }
  static Stream<QuerySnapshot> getFinanceRecords() => db.collection('finance').orderBy('date', descending: true).snapshots();
  static Future<void> deleteFinanceRecord(String id) => db.collection('finance').doc(id).delete();

  // ====== NHIÊN LIỆU ======
  static Future<void> saveFuel(FuelModel fuel) async {
    await db.collection('fuel').doc(fuel.id).set({'id': fuel.id, 'name': fuel.name, 'unit': fuel.unit, 'stock': fuel.stock, 'unitPrice': fuel.unitPrice, 'supplier': fuel.supplier, 'updatedAt': FieldValue.serverTimestamp()});
  }
  static Stream<QuerySnapshot> getFuels() => db.collection('fuel').orderBy('name').snapshots();
  static Future<void> deleteFuel(String id) => db.collection('fuel').doc(id).delete();

  static Future<void> syncAllData({required List<WarehouseItem> warehouseItems, required List<MachineModel> machines, required List<EmployeeModel> employees, required List<TaskModel> tasks, required List<FinanceRecord> financeRecords, required List<FuelModel> fuels}) async {
    final batch = db.batch();
    for (final item in warehouseItems) { batch.set(db.collection('warehouse').doc(item.id), {'id': item.id, 'name': item.name, 'unit': item.unit, 'importPrice': item.importPrice, 'supplier': item.supplier, 'stock': item.stock, 'updatedAt': FieldValue.serverTimestamp()}); }
    for (final machine in machines) { batch.set(db.collection('machines').doc(machine.id), {'id': machine.id, 'name': machine.name, 'type': machine.type, 'manufacturer': machine.manufacturer, 'year': machine.year, 'status': machine.status, 'totalHours': machine.totalHours, 'fuelConsumption': machine.fuelConsumption, 'currentFieldId': machine.currentFieldId, 'updatedAt': FieldValue.serverTimestamp()}); }
    for (final employee in employees) { batch.set(db.collection('employees').doc(employee.id), {'id': employee.id, 'name': employee.name, 'position': employee.position, 'department': employee.department, 'dailyRate': employee.dailyRate, 'phone': employee.phone, 'address': employee.address, 'isActive': employee.isActive, 'updatedAt': FieldValue.serverTimestamp()}); }
    for (final task in tasks) { batch.set(db.collection('tasks').doc(task.id), {'id': task.id, 'title': task.title, 'description': task.description, 'priority': task.priority.index, 'status': task.status.index, 'dueDate': task.dueDate.toIso8601String(), 'completedDate': task.completedDate?.toIso8601String(), 'assignedTo': task.assignedTo, 'assignedToName': task.assignedToName, 'fieldId': task.fieldId, 'fieldName': task.fieldName, 'machineId': task.machineId, 'machineName': task.machineName, 'tags': task.tags, 'createdAt': task.createdAt.toIso8601String(), 'updatedAt': FieldValue.serverTimestamp()}); }
    for (final record in financeRecords) { batch.set(db.collection('finance').doc(record.id), {'id': record.id, 'fieldId': record.fieldId, 'fieldName': record.fieldName, 'date': record.date.toIso8601String(), 'type': record.type.index, 'category': record.category, 'amount': record.amount, 'description': record.description, 'machineId': record.machineId, 'machineName': record.machineName, 'updatedAt': FieldValue.serverTimestamp()}); }
    for (final fuel in fuels) { batch.set(db.collection('fuel').doc(fuel.id), {'id': fuel.id, 'name': fuel.name, 'unit': fuel.unit, 'stock': fuel.stock, 'unitPrice': fuel.unitPrice, 'supplier': fuel.supplier, 'updatedAt': FieldValue.serverTimestamp()}); }
    await batch.commit();
  }

  static Future<bool> checkConnection() async {
    try {
      await db.collection('_test').doc('test').set({'test': true});
      await db.collection('_test').doc('test').delete();
      return true;
    } catch (_) { return false; }
  }
}
