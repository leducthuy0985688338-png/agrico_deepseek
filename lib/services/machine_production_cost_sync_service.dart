import '../models/machine_model.dart';
import '../models/production_cost_model.dart';
import 'production_cost_database.dart';
import 'production_season_database.dart';

/// Converts machine field-work time into the production-cost ledger.
///
/// The hourly rate belongs to the machine master data. When it is zero we do
/// not invent a cost; the work record remains available and can be synced once
/// a rate is configured. The source/sourceId pair makes updates idempotent.
class MachineProductionCostSyncService {
  final ProductionCostDatabase _costDatabase;
  final ProductionSeasonDatabase _seasonDatabase;

  MachineProductionCostSyncService({
    ProductionCostDatabase? costDatabase,
    ProductionSeasonDatabase? seasonDatabase,
  })  : _costDatabase = costDatabase ?? ProductionCostDatabase(),
        _seasonDatabase = seasonDatabase ?? ProductionSeasonDatabase();

  Future<ProductionCostModel?> sync({
    required MachineModel machine,
    required MachineFieldRecord work,
    required double costPerHour,
  }) async {
    if (work.fieldId.isEmpty || work.hoursWorked <= 0 || costPerHour <= 0) {
      return null;
    }

    final seasonId = await _resolveSeasonId(work.fieldId);
    if (seasonId == null || seasonId.isEmpty) return null;

    final sourceId = _sourceId(machine.id, work);
    final existing = await _costDatabase.getBySource('machine', sourceId);
    final amount = work.hoursWorked * costPerHour;

    final record = ProductionCostModel(
      id: existing?.id ?? 'MACHINE-COST-$sourceId',
      fieldId: work.fieldId,
      seasonId: seasonId,
      category: ProductionCostCategory.machine,
      date: work.startDate,
      itemName: machine.name,
      quantity: work.hoursWorked,
      unit: 'giờ',
      unitPrice: costPerHour,
      amount: amount,
      machineId: machine.id,
      notes: 'Chi phí vận hành máy trên ${work.fieldName}',
      source: 'machine',
      sourceId: sourceId,
    );

    await _costDatabase.upsert(record);
    return record;
  }

  Future<String?> _resolveSeasonId(String fieldId) async {
    final season = await _seasonDatabase.getLatestByField(fieldId);
    return season?.id;
  }

  String _sourceId(String machineId, MachineFieldRecord work) =>
      '$machineId:${work.fieldId}:${work.startDate.toUtc().toIso8601String()}';
}
