import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../services/cost_driver_trace_service.dart';
import '../services/season_cost_driver_analysis_service.dart';

class CostDriverTraceScreen extends StatefulWidget {
  final FieldModel field;
  final ProductionSeasonModel season;
  final SeasonCostDriverChange driver;

  const CostDriverTraceScreen({
    super.key,
    required this.field,
    required this.season,
    required this.driver,
  });

  @override
  State<CostDriverTraceScreen> createState() => _CostDriverTraceScreenState();
}

class _CostDriverTraceScreenState extends State<CostDriverTraceScreen> {
  late Future<List<CostDriverTraceRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CostDriverTraceRow>> _load() {
    return const CostDriverTraceService().trace(
      season: widget.season,
      driver: widget.driver,
    );
  }

  void _reload() => setState(() => _future = _load());

  String _money(double value) => '${value.toStringAsFixed(0)} đ';

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Truy nguyên khoản chi'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<List<CostDriverTraceRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton(onPressed: _reload, child: const Text('Thử lại')),
              ),
            );
          }

          final rows = snapshot.data ?? const <CostDriverTraceRow>[];
          final total = rows.fold<double>(0, (sum, row) => sum + row.amount);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.field.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(widget.season.name),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cost Driver', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(widget.driver.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(widget.driver.category.label),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _summary('Bản ghi', '${rows.length}')),
                          Expanded(child: _summary('Tổng chi', _money(total))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Các khoản chi cụ thể', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Card(child: ListTile(title: Text('Không tìm thấy bản ghi chi phí phù hợp.'))),
              ...rows.map(
                (row) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(_icon(row.category))),
                    title: Text(_money(row.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${row.quantity.toStringAsFixed(2)} ${row.unit} × ${_money(row.unitPrice)}\n'
                      '${_date(widget.season.startDate)} • ${row.source ?? row.category.label}',
                    ),
                    isThreeLine: true,
                    trailing: row.sourceId == null ? null : Text(row.sourceId!, style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summary(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      );

  IconData _icon(ProductionCostCategory category) {
    switch (category) {
      case ProductionCostCategory.material:
        return Icons.inventory_2;
      case ProductionCostCategory.labor:
        return Icons.people;
      case ProductionCostCategory.machine:
        return Icons.agriculture;
      case ProductionCostCategory.fuel:
        return Icons.local_gas_station;
    }
  }
}
