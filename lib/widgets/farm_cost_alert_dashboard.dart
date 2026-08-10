import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../services/farm_cost_alert_service.dart';

class FarmCostAlertDashboard extends StatefulWidget {
  final List<FieldModel> fields;
  final List<ProductionSeasonModel> seasons;

  const FarmCostAlertDashboard({
    super.key,
    required this.fields,
    required this.seasons,
  });

  @override
  State<FarmCostAlertDashboard> createState() => _FarmCostAlertDashboardState();
}

class _FarmCostAlertDashboardState extends State<FarmCostAlertDashboard> {
  late Future<List<FarmCostAlertRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant FarmCostAlertDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields || oldWidget.seasons != widget.seasons) {
      _future = _load();
    }
  }

  Future<List<FarmCostAlertRow>> _load() {
    return FarmCostAlertService().load(
      fields: widget.fields,
      seasons: widget.seasons,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FarmCostAlertRow>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Không tải được cảnh báo chi phí'),
              subtitle: Text('${snapshot.error}'),
            ),
          );
        }

        final rows = [...snapshot.data ?? const <FarmCostAlertRow>[]]
          ..sort((a, b) => b.variance.compareTo(a.variance));
        final alerts = rows.where((row) => row.isOverBudget).toList();
        final critical = rows.where((row) => row.isCritical).length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      alerts.isEmpty ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: alerts.isEmpty ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Cảnh báo chi phí sản xuất',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Làm mới',
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                Text(
                  '${alerts.length} vụ vượt mức tham chiếu • $critical vụ cần ưu tiên',
                  style: TextStyle(
                    color: critical > 0 ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (alerts.isEmpty)
                  const Text('Chưa phát hiện vụ có chi phí cao hơn mức tham chiếu chung.'),
                ...alerts.take(5).map(
                  (row) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      row.isCritical ? Icons.priority_high : Icons.warning_amber,
                      color: row.isCritical ? Colors.red : Colors.orange,
                    ),
                    title: Text(row.season.name),
                    subtitle: Text(
                      '${row.season.crop} • ${row.actualPerHa.toStringAsFixed(0)} đ/ha '
                      'vs ${row.benchmarkPerHa.toStringAsFixed(0)} đ/ha',
                    ),
                    trailing: Text(
                      '+${row.variance.toStringAsFixed(0)} đ',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
