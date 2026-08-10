import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/production_season_model.dart';
import '../providers/harvest_provider.dart';
import '../providers/production_cost_provider.dart';

class ProductionCostDashboardScreen extends StatefulWidget {
  final ProductionSeasonModel season;
  const ProductionCostDashboardScreen({super.key, required this.season});

  @override
  State<ProductionCostDashboardScreen> createState() => _ProductionCostDashboardScreenState();
}

class _ProductionCostDashboardScreenState extends State<ProductionCostDashboardScreen> {
  late final ProductionCostProvider _costProvider;
  late final HarvestProvider _harvestProvider;

  @override
  void initState() {
    super.initState();
    _costProvider = context.read<ProductionCostProvider>()
      ..loadForSeason(widget.season.id);
    _harvestProvider = context.read<HarvestProvider>()
      ..loadForSeason(widget.season.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hiệu quả sản xuất • ${widget.season.name}')),
      body: AnimatedBuilder(
        animation: Listenable.merge([_costProvider, _harvestProvider]),
        builder: (context, _) {
          if (_costProvider.isLoading || _harvestProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = _costProvider.summaryForSeason(
            seasonId: widget.season.id,
            fieldId: widget.season.fieldId,
          );
          final areaHa = widget.season.plannedArea / 10000;
          final revenue = _harvestProvider.totalRevenue(widget.season.id);
          final quantity = _harvestProvider.totalQuantity(widget.season.id);
          final yieldPerHa = areaHa > 0 ? quantity / areaHa : 0;
          final profit = revenue - summary.totalCost;
          final costPerHa = summary.costPerHa(areaHa);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _heroCard(summary.totalCost, costPerHa, revenue, profit),
              const SizedBox(height: 12),
              _sectionTitle('Cơ cấu chi phí'),
              _categoryGrid(summary),
              const SizedBox(height: 12),
              _sectionTitle('Hiệu quả sản xuất'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _metricRow('Diện tích', '${areaHa.toStringAsFixed(2)} ha'),
                    _metricRow('Sản lượng', '${quantity.toStringAsFixed(1)} kg'),
                    _metricRow('Năng suất', '${yieldPerHa.toStringAsFixed(1)} kg/ha'),
                    _metricRow('Doanh thu', _money(revenue)),
                    _metricRow('Tổng chi phí', _money(summary.totalCost)),
                    _metricRow('Chi phí/ha', _money(costPerHa)),
                    _metricRow('Lợi nhuận tạm tính', _money(profit), highlight: true),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(profit >= 0 ? Icons.trending_up : Icons.warning_amber_rounded),
                  title: Text(profit >= 0 ? 'Đang có lãi' : 'Đang âm chi phí'),
                  subtitle: Text(
                    revenue <= 0
                        ? 'Chưa có doanh thu thu hoạch; lợi nhuận sẽ được cập nhật khi có dữ liệu bán hàng.'
                        : 'Biên lợi nhuận tạm tính: ${_percent(revenue > 0 ? profit / revenue : 0)}',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _heroCard(double total, double costPerHa, double revenue, double profit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TỔNG QUAN GIÁ THÀNH', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_money(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Chi phí/ha: ${_money(costPerHa)}'),
          const Divider(height: 24),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _miniMetric('Doanh thu', _money(revenue)),
              _miniMetric('Lợi nhuận', _money(profit)),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _categoryGrid(dynamic summary) {
    final items = [
      ('Vật tư', summary.material, Icons.inventory_2),
      ('Nhân công', summary.labor, Icons.groups),
      ('Máy móc', summary.machine, Icons.precision_manufacturing),
      ('Nhiên liệu', summary.fuel, Icons.local_gas_station),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(item.$3),
              const Spacer(),
              Text(item.$1, style: Theme.of(context).textTheme.bodySmall),
              Text(_money(item.$2), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  Widget _metricRow(String label, String value, {bool highlight = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [Expanded(child: Text(label)), Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: highlight ? 16 : 14))]),
      );

  Widget _miniMetric(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12)), const SizedBox(height: 2), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]);

  String _money(double value) => '${value.toStringAsFixed(0)} đ';
  String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
}
