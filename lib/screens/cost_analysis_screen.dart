import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../providers/harvest_provider.dart';
import '../providers/production_cost_provider.dart';
import '../providers/production_season_provider.dart';

class CostAnalysisScreen extends StatefulWidget {
  final List<FieldModel> fields;

  const CostAnalysisScreen({super.key, required this.fields});

  @override
  State<CostAnalysisScreen> createState() => _CostAnalysisScreenState();
}

class _CostAnalysisScreenState extends State<CostAnalysisScreen> {
  late Future<_CostAnalysisData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CostAnalysisData> _load() async {
    final categoryTotals = <ProductionCostCategory, double>{
      for (final category in ProductionCostCategory.values) category: 0,
    };
    double revenue = 0;
    double totalCost = 0;
    double totalAreaHa = 0;
    int seasonCount = 0;

    for (final field in widget.fields) {
      totalAreaHa += field.area / 10000;
      final seasons = ProductionSeasonProvider();
      try {
        await seasons.loadForField(field.id);
        seasonCount += seasons.seasonsForField(field.id).length;

        for (final season in seasons.seasonsForField(field.id)) {
          final costs = ProductionCostProvider();
          final harvest = HarvestProvider();
          try {
            await Future.wait([
              costs.loadForSeason(season.id),
              harvest.loadForSeason(season.id),
            ]);
            totalCost += costs.totalCost(season.id);
            revenue += harvest.totalRevenue(season.id);
            final byCategory = costs.byCategory(season.id);
            for (final entry in byCategory.entries) {
              categoryTotals[entry.key] =
                  (categoryTotals[entry.key] ?? 0) + entry.value;
            }
          } finally {
            costs.dispose();
            harvest.dispose();
          }
        }
      } finally {
        seasons.dispose();
      }
    }

    return _CostAnalysisData(
      categoryTotals: categoryTotals,
      revenue: revenue,
      totalCost: totalCost,
      totalAreaHa: totalAreaHa,
      seasonCount: seasonCount,
    );
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phân tích nguyên nhân lợi nhuận'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: FutureBuilder<_CostAnalysisData>(
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
                    const Text('Không thể tải dữ liệu phân tích chi phí.'),
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

          final data = snapshot.data!;
          final profit = data.revenue - data.totalCost;
          final margin = data.revenue > 0 ? profit / data.revenue : 0.0;
          final categories = data.categoryTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final top = categories.isEmpty ? null : categories.first;
          final topShare = data.totalCost > 0 && top != null
              ? top.value / data.totalCost
              : 0.0;
          final costPerHa = data.totalAreaHa > 0
              ? data.totalCost / data.totalAreaHa
              : 0.0;
          final profitPerHa = data.totalAreaHa > 0
              ? profit / data.totalAreaHa
              : 0.0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '🔎 Vì sao lợi nhuận tăng/giảm?',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.fields.length} thửa • ${data.seasonCount} vụ • ${data.totalAreaHa.toStringAsFixed(2)} ha',
              ),
              const SizedBox(height: 16),
              _OverviewCard(
                revenue: data.revenue,
                cost: data.totalCost,
                profit: profit,
                margin: margin,
              ),
              const SizedBox(height: 16),
              const Text(
                '💸 Cơ cấu chi phí',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...categories.map(
                (entry) => _CategoryCard(
                  category: entry.key,
                  amount: entry.value,
                  total: data.totalCost,
                ),
              ),
              const SizedBox(height: 8),
              _InsightCard(
                topCategory: top?.key.label ?? 'Chưa có dữ liệu',
                topAmount: top?.value ?? 0,
                topShare: topShare,
                costPerHa: costPerHa,
                profitPerHa: profitPerHa,
                profit: profit,
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Phân tích được tính trực tiếp từ sổ chi phí và dữ liệu thu hoạch của các vụ. '
                    'Mục tiêu là chỉ ra khoản chi phí đang tác động lớn nhất đến lợi nhuận để ưu tiên kiểm soát.',
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

class _CostAnalysisData {
  final Map<ProductionCostCategory, double> categoryTotals;
  final double revenue;
  final double totalCost;
  final double totalAreaHa;
  final int seasonCount;

  const _CostAnalysisData({
    required this.categoryTotals,
    required this.revenue,
    required this.totalCost,
    required this.totalAreaHa,
    required this.seasonCount,
  });
}

class _OverviewCard extends StatelessWidget {
  final double revenue;
  final double cost;
  final double profit;
  final double margin;

  const _OverviewCard({
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.margin,
  });

  String _money(double value) => '${value.toStringAsFixed(0)} đ';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetricRow(label: 'Doanh thu', value: _money(revenue)),
            _MetricRow(label: 'Tổng chi phí', value: _money(cost)),
            _MetricRow(
              label: 'Lợi nhuận',
              value: _money(profit),
              emphasized: true,
              negative: profit < 0,
            ),
            _MetricRow(
              label: 'Biên lợi nhuận',
              value: '${(margin * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;
  final bool negative;

  const _MetricRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.negative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.bold : FontWeight.w600,
              color: emphasized ? (negative ? Colors.red : Colors.green) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final ProductionCostCategory category;
  final double amount;
  final double total;

  const _CategoryCard({
    required this.category,
    required this.amount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final share = total > 0 ? amount / total : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('${amount.toStringAsFixed(0)} đ'),
                const SizedBox(width: 8),
                Text('${(share * 100).toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(value: share.clamp(0.0, 1.0)),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String topCategory;
  final double topAmount;
  final double topShare;
  final double costPerHa;
  final double profitPerHa;
  final double profit;

  const _InsightCard({
    required this.topCategory,
    required this.topAmount,
    required this.topShare,
    required this.costPerHa,
    required this.profitPerHa,
    required this.profit,
  });

  @override
  Widget build(BuildContext context) {
    final loss = profit < 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🧠 Nhận định tự động',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _InsightRow(
              icon: Icons.priority_high,
              title: 'Khoản cần ưu tiên kiểm soát',
              text: '$topCategory • ${topAmount.toStringAsFixed(0)} đ (${(topShare * 100).toStringAsFixed(1)}% tổng chi phí)',
            ),
            _InsightRow(
              icon: Icons.price_check,
              title: 'Chi phí bình quân',
              text: '${costPerHa.toStringAsFixed(0)} đ/ha',
            ),
            _InsightRow(
              icon: loss ? Icons.warning_amber_rounded : Icons.trending_up,
              title: loss ? 'Cảnh báo lợi nhuận' : 'Tình trạng lợi nhuận',
              text: loss
                  ? 'Đang âm ${profitPerHa.abs().toStringAsFixed(0)} đ/ha. Cần rà soát khoản chi lớn nhất trước.'
                  : 'Đang dương ${profitPerHa.toStringAsFixed(0)} đ/ha. Có thể tối ưu thêm khoản chi lớn nhất để tăng biên lợi nhuận.',
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InsightRow({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
