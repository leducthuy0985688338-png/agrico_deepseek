import 'package:flutter/material.dart';
import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../services/farm_dashboard_service.dart';

class FarmKpiCard extends StatefulWidget {
  final List<FieldModel> fields;
  final List<ProductionSeasonModel> seasons;
  const FarmKpiCard({super.key, required this.fields, required this.seasons});
  @override State<FarmKpiCard> createState() => _FarmKpiCardState();
}

class _FarmKpiCardState extends State<FarmKpiCard> {
  Future<FarmDashboardMetrics>? _future;
  @override void initState() { super.initState(); _refresh(); }
  @override void didUpdateWidget(covariant FarmKpiCard oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.fields != widget.fields || oldWidget.seasons != widget.seasons) _refresh(); }
  void _refresh() { _future = FarmDashboardMetrics.calculate(fields: widget.fields, seasons: widget.seasons); }

  @override
  Widget build(BuildContext context) => FutureBuilder<FarmDashboardMetrics>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
      final m = snapshot.data!;
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tổng quan trang trại', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Kpi('Diện tích', '${m.areaHa.toStringAsFixed(1)} ha'), _Kpi('Thửa đất', '${m.fieldCount}'),
          _Kpi('Vụ sản xuất', '${m.seasonCount}'), _Kpi('Sản lượng', '${m.totalHarvest.toStringAsFixed(1)} kg'),
          _Kpi('Chi phí', _money(m.totalCost)), _Kpi('Doanh thu', _money(m.totalRevenue)),
          _Kpi('Lợi nhuận', _money(m.totalProfit)), _Kpi('LN/ha', _money(m.profitPerHa)),
        ]),
      ])));
    },
  );
  String _money(double v) => '${v.toStringAsFixed(0)} đ';
}

class _Kpi extends StatelessWidget {
  final String label; final String value;
  const _Kpi(this.label, this.value);
  @override
  Widget build(BuildContext context) => Container(
    width: 145, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Theme.of(context).colorScheme.surfaceContainerHighest),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    ]),
  );
}
