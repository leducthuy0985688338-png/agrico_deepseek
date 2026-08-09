import '../models/employee_model.dart';
import '../models/production_cost_model.dart';
import 'production_cost_database.dart';
import 'production_season_database.dart';

/// Converts production attendance into a labor production-cost entry.
///
/// Attendance is the source of truth. The attendance check-in timestamp is
/// used in sourceId so repeated synchronization updates the same cost row
/// instead of creating duplicate labor costs.
class LaborProductionCostSyncService {
  final ProductionCostDatabase _costDatabase;
  final ProductionSeasonDatabase _seasonDatabase;

  LaborProductionCostSyncService({
    ProductionCostDatabase? costDatabase,
    ProductionSeasonDatabase? seasonDatabase,
  })  : _costDatabase = costDatabase ?? ProductionCostDatabase(),
        _seasonDatabase = seasonDatabase ?? ProductionSeasonDatabase();

  Future<ProductionCostModel?> sync({
    required AttendanceRecord attendance,
    required EmployeeModel employee,
  }) async {
    final fieldId = attendance.fieldId;
    if (fieldId == null || fieldId.isEmpty) return null;
    if (attendance.checkOut == null || attendance.hours <= 0) return null;

    final season = await _seasonDatabase.getLatestByField(fieldId);
    if (season == null) return null;

    final sourceId = '${employee.id}|${fieldId}|${attendance.checkIn.toIso8601String()}';
    final existing = await _costDatabase.getBySource('labor', sourceId);

    // One standard workday is 8 hours. This preserves overtime/partial-day
    // attendance while keeping the employee's configured daily rate as the
    // unit price.
    final workDays = attendance.hours / 8.0;
    final amount = workDays * employee.dailyRate;

    final record = ProductionCostModel(
      id: existing?.id ?? 'LABOR-COST-${attendance.checkIn.microsecondsSinceEpoch}',
      fieldId: fieldId,
      seasonId: season.id,
      category: ProductionCostCategory.labor,
      date: attendance.date,
      itemName: 'Công lao động • ${employee.name}',
      quantity: workDays,
      unit: 'ngày công',
      unitPrice: employee.dailyRate,
      amount: amount,
      employeeId: employee.id,
      notes: 'Chấm công ${attendance.hours.toStringAsFixed(2)} giờ tại thửa $fieldId',
      source: 'labor',
      sourceId: sourceId,
    );

    await _costDatabase.upsert(record);
    return record;
  }
}
