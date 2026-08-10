import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../providers/dashboard_provider.dart';
import '../providers/field_provider.dart';
import '../services/farm_season_loader_service.dart';
import '../widgets/farm_cost_alert_dashboard.dart';
import '../widgets/farm_cost_cause_analysis_card.dart';
import 'cost_analysis_screen.dart';
import 'field_detail_screen.dart';
import 'field_list_screen.dart';
import 'field_performance_screen.dart';
import 'overall_field_map_screen.dart';
import 'report_screen.dart';

class FarmDashboardScreen extends StatefulWidget {
  const FarmDashboardScreen({super.key});

  @override
  State<FarmDashboardScreen> createState() => _FarmDashboardScreenState();
}

class _FarmDashboardScreenState extends State<FarmDashboardScreen> {
  final DashboardProvider _dashboard = DashboardProvider();
  final FieldProvider _fields = FieldProvider();
  late Future<List<ProductionSeasonModel>> _seasonsFuture;

  @override
  void initState() {
    super.initState();
    _seasonsFuture = _loadSeasons();
  }

  @override
  void dispose() {
    _dashboard.dispose();
    _fields.dispose();
    super.dispose();
  }

  Future<List<ProductionSeasonModel>> _loadSeasons() {
    final ids = _fields.fields.map((field) => field.id).toList(growable: false);
    return FarmSeasonLoaderService().loadForFields(ids);
  }

  Future<void> _refresh() async {
    setState(() => _seasonsFuture = _loadSeasons());
    await _seasonsFuture;
  }

  void _open(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _openField(String fieldId) {
    final field = _fields.getFieldById(fieldId);
    if (field != null) {
      _open(FieldDetailScreen(field: field));
    }
  }

  String _money(num value) {
    final amount = value.toDouble();
    if (amount.abs() >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(2)} tỷ';
    }
    if (amount.abs() >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)} triệu';
    }
    return '${amount.toStringAsFixed(0)} đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard quản trị trang trại'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _fields,
        builder: (context, _) {
          final fields = _fields.fields;
          final areaHa = fields.fold<double>(0, (sum, field) => sum + field.area) / 10000;
          final crops = <String, double>{};
          final statuses = <String, int>{};

          for (final field in fields) {
            final crop = field.crop.isEmpty ? 'Chưa xác định' : field.crop;
            crops[crop] = (crops[crop] ?? 0) + field.area / 10000;
            final status = field.status.isEmpty ? 'Chưa xác định' : field.status;
            statuses[status] = (statuses[status] ?? 0) + 1;
          }

          final revenue = _dashboard.totalRevenue.toDouble();
          final cost = _dashboard.totalCost.toDouble();
          final profit = _dashboard.totalProfit.toDouble();
          final margin = revenue == 0 ? 0.0 : profit / revenue;
          final costPerHa = areaHa == 0 ? 0.0 : cost / areaHa;
          final topFields = _dashboard.getTopFieldsByProfit(limit: 5);
          final highCost = _dashboard.getHighestCostFields(limit: 5);

          return FutureBuilder<List<ProductionSeasonModel>>(
            future: _seasonsFuture,
            builder: (context, snapshot) {
              final seasons = snapshot.data ?? const <ProductionSeasonModel>[];

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Tổng quan hôm nay',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('Trung tâm điều hành đất, sản xuất và tài chính của AGRICO.'),
                    const SizedBox(height: 16),
                    _QuickActions(onOpen: _open, fields: fields),
                    const SizedBox(height: 16),
                    _KpiGrid(
                      areaHa: areaHa,
                      fieldCount: fields.length,
                      seasonCount: seasons.length,
                      revenue: _money(revenue),
                      cost: _money(cost),
                      profit: _money(profit),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else if (snapshot.hasError)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: const Text('Không tải được dữ liệu vụ sản xuất'),
                          subtitle: Text('${snapshot.error}'),
                        ),
                      )
                    else ...[
                      FarmCostAlertDashboard(fields: fields, seasons: seasons),
                      const SizedBox(height: 12),
                      FarmCostCauseAnalysisCard(fields: fields, seasons: seasons),
                    ],
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '💰 Hiệu quả tài chính',
                      child: Column(
                        children: [
                          _Metric(label: 'Doanh thu', value: _money(revenue), icon: Icons.arrow_upward),
                          _Metric(label: 'Tổng chi phí', value: _money(cost), icon: Icons.arrow_downward),
                          _Metric(label: 'Lợi nhuận', value: _money(profit), icon: Icons.account_balance_wallet),
                          _Metric(label: 'Chi phí bình quân/ha', value: _money(costPerHa), icon: Icons.price_check),
                          _Metric(label: 'Biên lợi nhuận', value: '${(margin * 100).toStringAsFixed(1)}%', icon: Icons.percent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '🌱 Cơ cấu diện tích cây trồng',
                      child: crops.isEmpty
                          ? const Text('Chưa có dữ liệu thửa đất.')
                          : Column(
                              children: [
                                for (final entry in crops.entries)
                                  _ProgressRow(
                                    label: entry.key,
                                    value: entry.value,
                                    total: areaHa,
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '🚜 Trạng thái sản xuất',
                      child: statuses.isEmpty
                          ? const Text('Chưa có dữ liệu.')
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final entry in statuses.entries)
                                  Chip(
                                    avatar: const Icon(Icons.circle, size: 12),
                                    label: Text('${entry.key}: ${entry.value}'),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '🏆 Top thửa theo lợi nhuận/ha',
                      trailing: TextButton.icon(
                        onPressed: () => _open(const FieldPerformanceScreen()),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Xem tất cả'),
                      ),
                      child: topFields.isEmpty
                          ? const Text('Chưa có báo cáo tài chính theo thửa.')
                          : Column(
                              children: [
                                for (final row in topFields)
                                  _FieldFinanceRow(
                                    row: row,
                                    onTap: () => _openField(row['fieldId'] as String),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '⚠️ Thửa có chi phí/ha cao',
                      child: highCost.isEmpty
                          ? const Text('Chưa có dữ liệu chi phí.')
                          : Column(
                              children: [
                                for (final row in highCost)
                                  _FieldCostRow(
                                    row: row,
                                    onTap: () => _openField(row['fieldId'] as String),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final void Function(Widget screen) onOpen;
  final List<FieldModel> fields;

  const _QuickActions({required this.onOpen, required this.fields});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Action('Danh sách thửa', Icons.grid_view, () => onOpen(const FieldListScreen())),
            _Action('Hiệu quả thửa', Icons.insights, () => onOpen(const FieldPerformanceScreen())),
            _Action('Phân tích chi phí', Icons.analytics_outlined, () => onOpen(CostAnalysisScreen(fields: fields))),
            _Action('Bản đồ tổng thể', Icons.map, () => onOpen(const OverallFieldMapScreen())),
            _Action('Báo cáo', Icons.assessment, () => onOpen(const ReportScreen())),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _Action(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final double areaHa;
  final int fieldCount;
  final int seasonCount;
  final String revenue;
  final String cost;
  final String profit;

  const _KpiGrid({
    required this.areaHa,
    required this.fieldCount,
    required this.seasonCount,
    required this.revenue,
    required this.cost,
    required this.profit,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiCard(Icons.landscape, 'Diện tích', '${areaHa.toStringAsFixed(2)} ha'),
      _KpiCard(Icons.grid_view, 'Số thửa', '$fieldCount'),
      _KpiCard(Icons.agriculture, 'Vụ sản xuất', '$seasonCount'),
      _KpiCard(Icons.trending_up, 'Doanh thu', revenue),
      _KpiCard(Icons.trending_down, 'Chi phí', cost),
      _KpiCard(Icons.account_balance_wallet, 'Lợi nhuận', profit),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: cards,
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _KpiCard(this.icon, this.title, this.value);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.green),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(radius: 17, child: Icon(icon, size: 17)),
      title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double value;
  final double total;

  const _ProgressRow({required this.label, required this.value, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (value / total).clamp(0.0, 1.0).toDouble() : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text('${value.toStringAsFixed(2)} ha'),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(value: ratio),
        ],
      ),
    );
  }
}

class _FieldFinanceRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  const _FieldFinanceRow({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final profit = (row['profit'] as num).toDouble();
    final perHa = (row['profitPerHa'] as num).toDouble();
    final name = row['field'] as String;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0])),
      title: Text(name),
      subtitle: Text('${(row['areaHa'] as num).toStringAsFixed(2)} ha • LN/ha: ${perHa.toStringAsFixed(0)} đ'),
      trailing: Text(
        '${profit.toStringAsFixed(0)} đ',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: profit >= 0 ? Colors.green : Colors.red,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _FieldCostRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  const _FieldCostRow({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cost = (row['costPerHa'] as num).toDouble();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: Text(row['field'] as String),
      subtitle: Text('${(row['areaHa'] as num).toStringAsFixed(2)} ha'),
      trailing: Text(
        '${cost.toStringAsFixed(0)} đ/ha',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onTap: onTap,
    );
  }
}
