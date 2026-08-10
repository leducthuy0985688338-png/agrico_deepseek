import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/models/production_cost_model.dart';
import 'package:agrico_deepseek/services/cost_driver_trace_service.dart';

void main() {
  group('CostDriverTraceRow', () {
    test('keeps source and cost details for drill-down', () {
      const row = CostDriverTraceRow(
        seasonId: 'season-1',
        fieldId: 'field-01',
        driverLabel: 'Phân bón',
        category: ProductionCostCategory.material,
        date: DateTime(2026, 8, 10),
        amount: 2500000,
        quantity: 100,
        unit: 'kg',
        unitPrice: 25000,
        source: 'warehouse',
        sourceId: 'issue-01',
        employeeId: 'employee-01',
        machineId: 'machine-01',
        notes: 'Bón phân đợt 1',
        recordId: 'cost-01',
      );

      expect(row.fieldId, 'field-01');
      expect(row.amount, 2500000);
      expect(row.sourceId, 'issue-01');
      expect(row.notes, 'Bón phân đợt 1');
    });
  });
}
