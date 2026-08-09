import 'package:flutter/material.dart';

import '../models/production_season_model.dart';
import '../providers/production_log_provider.dart';

class ProductionDashboardCard extends StatefulWidget {
  final ProductionSeasonModel season;
  const ProductionDashboardCard({super.key, required this.season});

  @override
  State<ProductionDashboardCard> createState() => _ProductionDashboardCardState();
}

class _ProductionDashboardCardState extends State<ProductionDashboardCard> {
  late final ProductionLogProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = ProductionLogProvider()..loadForSeason(widget.season.id);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final logs = _provider.logsForSeason(widget.season.id);
        final total = _provider.totalCost(widget.season.id);
        final hectares = widget.season.plannedArea / 10000;
        final perHa = hectares > 0 ? total / hectares : 0;
        final groups = <String, double>{};
        for (final log in logs) {
          groups[log.activityType] = (groups[log.activityType] ?? 0) + log.cost;
        }
        final top = groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tổng quan vụ sản xuất', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Metric(label: 'Chi phí', value: _money(total)),
                    _Metric(label: 'Chi phí/ha', value: _money(perHa)),
                    _Metric(label: 'Hoạt động', value: '${logs.length}'),
                  ],
                ),
                if (top.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Phân bổ chi phí', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...top.take(5).map((entry) {
                    final ratio = total > 0 ? entry.value / total : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [Expanded(child: Text(entry.key)), Text(_money(entry.value))]),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: ratio),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _money(double value) => '${value.toStringAsFixed(0)} đ';
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
