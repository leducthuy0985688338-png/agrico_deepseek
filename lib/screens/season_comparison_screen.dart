import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../providers/harvest_provider.dart';
import '../providers/production_cost_provider.dart';
import '../services/season_economics_service.dart';

class SeasonComparisonScreen extends StatefulWidget {
  final FieldModel field;
  final List<ProductionSeasonModel> seasons;

  const SeasonComparisonScreen({
    super.key,
    required this.field,
    required this.seasons,
  });

  @override
  State<SeasonComparisonScreen> createState() => _SeasonComparisonScreenState();
}

class _SeasonComparisonScreenState extends State<SeasonComparisonScreen> {
  late Future<List<_SeasonComparisonData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_SeasonComparisonData>> _load() async {
    final result = <_SeasonComparisonData>[];
    for (final season in widget.seasons) {
      final costs = ProductionCostProvider();
      final harvest = HarvestProvider();
      try {
        await Future.wait([
          costs.loadForSeason(season.id),
          harvest.loadForSeason(season.id),
        ]);
        final economics = SeasonEconomics.calculate(
          plannedAreaSquareMeters: season.plannedArea,
          totalCost: costs.totalCost(season.id),
          totalRevenue: harvest.totalRevenue(season.id),
          totalQuantity: harvest.totalQuantity(season.id),
        );
        result.add(_SeasonComparisonData(season: season, economics: economics));
      } finally {
        costs.dispose();
        harvest.dispose();
      }
    }
    result.sort((a, b) => b.season.startDate.compareTo(a.season.startDate));
    return result;
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('So sánh các vụ sản xuất'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: FutureBuilder<List<_SeasonComparisonData>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    const Text('Không thể tải dữ liệu so sánh.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            );
          }

          final rows = snapshot.data ?? const <_SeasonComparisonData>[];
          if (rows.isEmpty) {
            return const Center(child: Text('Chưa có vụ sản xuất để so sánh.'));
          }

          final bestProfit = rows.reduce(
            (a, b) => a.economics.profitPerHa >= b.economics.profitPerHa ? a : b,
          );
          final totalRevenue = rows.fold<double>(
            0,
            (sum, row) => sum + row.economics.totalRevenue,
          );
          final totalCost = rows.fold<double>(
            0,
            (sum, row) => sum + row.economics.totalCost,
          );
          final totalProfit = rows.fold<double>(
            0,
            (sum, row) => sum + row.economics.profit,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Thửa • ${widget.field.name}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('${widget.field.crop} • ${rows.length} vụ'),
              const SizedBox(height: 16),
              _SummaryCard(
                bestSeason: bestProfit.season.name,
                revenue: totalRevenue,
                cost: totalCost,
                profit: totalProfit,
              ),
              const SizedBox(height: 16),
              const Text(
                '📈 Xu hướng hiệu quả theo vụ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _PerformanceCharts(rows: rows),
              const SizedBox(height: 16),
              const Text(
                '📊 Xếp hạng hiệu quả vụ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...rows.asMap().entries.map(
                    (entry) => _SeasonRow(rank: entry.key + 1, data: entry.value),
                  ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Biểu đồ dùng dữ liệu trực tiếp từ sổ chi phí và thu hoạch của từng vụ. '
                    'Thứ tự biểu đồ theo ngày bắt đầu vụ, còn bảng xếp hạng theo lợi nhuận/ha.',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SeasonComparisonData {
  final ProductionSeasonModel season;
  final SeasonEconomics economics;

  const _SeasonComparisonData({required this.season, required this.economics});
}

class _PerformanceCharts extends StatelessWidget {
  final List<_SeasonComparisonData> rows;

  const _PerformanceCharts({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ChartCard(
          title: 'Lợi nhuận/ha',
          subtitle: 'So sánh khả năng sinh lời giữa các vụ',
          child: SizedBox(
            height: 240,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _positiveMax(rows.map((r) => r.economics.profitPerHa)),
                minY: _negativeMin(rows.map((r) => r.economics.profitPerHa)),
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 48),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= rows.length) return const SizedBox.shrink();
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < rows.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: rows[i].economics.profitPerHa,
                          width: 18,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Năng suất',
          subtitle: 'Sản lượng bình quân theo ha',
          child: SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 48),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= rows.length) return const SizedBox.shrink();
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    spots: [
                      for (var i = 0; i < rows.length; i++)
                        FlSpot(i.toDouble(), rows[i].economics.yieldPerHa),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Doanh thu/ha và Chi phí/ha',
          subtitle: 'Nhìn nhanh khoảng cách giữa đầu vào và đầu ra',
          child: SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _positiveMax([
                  ...rows.map((r) => r.economics.revenuePerHa),
                  ...rows.map((r) => r.economics.costPerHa),
                ]),
                minY: 0,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 48),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= rows.length) return const SizedBox.shrink();
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < rows.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: rows[i].economics.revenuePerHa,
                          width: 10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        BarChartRodData(
                          toY: rows[i].economics.costPerHa,
                          width: 10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(label: 'Doanh thu/ha'),
            SizedBox(width: 16),
            _LegendDot(label: 'Chi phí/ha'),
          ],
        ),
      ],
    );
  }

  double _positiveMax(Iterable<double> values) {
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    return max <= 0 ? 1 : max * 1.2;
  }

  double _negativeMin(Iterable<double> values) {
    final min = values.fold<double>(0, (a, b) => b < a ? b : a);
    return min >= 0 ? 0 : min * 1.2;
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;

  const _LegendDot({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.circle, size: 9),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String bestSeason;
  final double revenue;
  final double cost;
  final double profit;

  const _SummaryCard({
    required this.bestSeason,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏆 Vụ hiệu quả nhất', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(bestSeason, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(height: 22),
            _metric('Tổng doanh thu', revenue),
            _metric('Tổng chi phí', cost),
            _metric('Tổng lợi nhuận', profit, emphasized: true),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, double value, {bool emphasized = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              '${value.toStringAsFixed(0)} đ',
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.bold : FontWeight.w600,
                color: emphasized ? Colors.green : null,
              ),
            ),
          ],
        ),
      );
}

class _SeasonRow extends StatelessWidget {
  final int rank;
  final _SeasonComparisonData data;

  const _SeasonRow({required this.rank, required this.data});

  @override
  Widget build(BuildContext context) {
    final e = data.economics;
    final profitColor = e.profitPerHa >= 0 ? Colors.green : Colors.red;
    final ratio = e.revenuePerHa > 0
        ? (e.profitPerHa / e.revenuePerHa).clamp(-1.0, 1.0)
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 17, child: Text('$rank')),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.season.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text(data.season.status, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${e.totalQuantity.toStringAsFixed(1)} kg')),
                Chip(label: Text('${e.yieldPerHa.toStringAsFixed(1)} kg/ha')),
                Chip(label: Text('CP ${e.costPerHa.toStringAsFixed(0)} đ/ha')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Lợi nhuận/ha',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${e.profitPerHa.toStringAsFixed(0)} đ/ha',
                  style: TextStyle(fontWeight: FontWeight.bold, color: profitColor),
                ),
              ],
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: ratio < 0 ? 0 : ratio),
          ],
        ),
      ),
    );
  }
}
