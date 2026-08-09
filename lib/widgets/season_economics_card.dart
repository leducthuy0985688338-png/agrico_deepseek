import 'package:flutter/material.dart';

import '../models/production_season_model.dart';
import '../providers/harvest_provider.dart';
import '../providers/production_cost_provider.dart';
import '../services/season_economics_service.dart';

class SeasonEconomicsCard extends StatefulWidget {
  final ProductionSeasonModel season;
  const SeasonEconomicsCard({super.key, required this.season});

  @override
  State<SeasonEconomicsCard> createState() => _SeasonEconomicsCardState();
}

class _SeasonEconomicsCardState extends State<SeasonEconomicsCard> {
  late final ProductionCostProvider _costs;
  late final HarvestProvider _harvest;

  @override
  void initState() {
    super.initState();
    _costs = ProductionCostProvider()..loadForSeason(widget.season.id);
    _harvest = HarvestProvider()..loadForSeason(widget.season.id);
  }

  @override
  void dispose() {
    _costs.dispose();
    _harvest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_costs, _harvest]),
      builder: (context, _) {
        final data = SeasonEconomics.calculate(
          plannedAreaSquareMeters: widget.season.plannedArea,
          totalCost: _costs.totalCost(widget.season.id),
          totalRevenue: _harvest.totalRevenue(widget.season.id),
          totalQuantity: _harvest.totalQuantity(widget.season.id),
        );
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hiệu quả kinh tế', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _row('Sản lượng', '${data.totalQuantity.toStringAsFixed(1)} kg'),
                _row('Năng suất', '${data.yieldPerHa.toStringAsFixed(1)} kg/ha'),
                _row('Doanh thu', _money(data.totalRevenue)),
                _row('Doanh thu/ha', _money(data.revenuePerHa)),
                _row('Chi phí', _money(data.totalCost)),
                _row('Chi phí/ha', _money(data.costPerHa)),
                const Divider(height: 20),
                _row('Lợi nhuận', _money(data.profit), emphasized: true),
                _row('Lợi nhuận/ha', _money(data.profitPerHa), emphasized: true),
                const SizedBox(height: 6),
                Text(
                  'Chi phí lấy từ sổ chi phí sản xuất của vụ (fieldId + seasonId).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, {bool emphasized = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.bold : FontWeight.w600,
                fontSize: emphasized ? 16 : null,
              ),
            ),
          ],
        ),
      );

  String _money(double value) => '${value.toStringAsFixed(0)} đ';
}
