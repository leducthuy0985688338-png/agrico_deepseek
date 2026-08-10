import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../providers/dashboard_provider.dart';
import '../providers/field_provider.dart';
import '../services/farm_season_loader_service.dart';
import '../widgets/farm_cost_alert_dashboard.dart';
import '../widgets/farm_cost_cause_analysis_card.dart';
import 'field_list_screen.dart';
import 'overall_field_map_screen.dart';
import 'field_performance_screen.dart';
import 'field_detail_screen.dart';
import 'cost_analysis_screen.dart';
import 'report_screen.dart';

class FarmDashboardScreen extends StatefulWidget {
  const FarmDashboardScreen({super.key});

  @override
  State<FarmDashboardScreen> createState() => _FarmDashboardScreenState();
}

class _FarmDashboardScreenState extends State<FarmDashboardScreen> {
  final DashboardProvider _dashboard = DashboardProvider();
  final FieldProvider _fields = FieldProvider();
  Future<List<ProductionSeasonModel>>? _seasonsFuture;

  @override
  void initState() {
    super.initState();
    _refreshSeasons();
  }

  @override
  void dispose() {
    _dashboard.dispose();
    super.dispose();
  }

  void _refreshSeasons() {
    final ids = _fields.fields.map((field) => field.id).toList(growable: false);
    _seasonsFuture = FarmSeasonLoaderService().loadForFields(ids);
  }

  String _money(num value) {
    final amount = value.toDouble();
    if (amount.abs() >= 1000000000) return '${(amount / 1000000000).toStringAsFixed(2)} tỷ';
    if (amount.abs() >= 1000000) return '${(amount / 1000000).toStringAsFixed(2)} triệu';
    return '${amount.toStringAsFixed(0)} đ';
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  void _openField(String fieldId) {
    final field = _fields.getFieldById(fieldId);
    if (field != null) _open(FieldDetailScreen(field: field));
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _refreshSeasons();
    });
    await _seasonsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard quản trị trang trại'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _refreshDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _fields,
        builder: (context, _) {
          final fields = _fields.fields;
          final areaHa = fields.fold<double>(0, (sum, f) => sum + f.area) / 10000;
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
          final margin = revenue > 0 ? profit / revenue : 0.0;
          final averageCostPerHa = areaHa > 0 ? cost / areaHa : 0.0;
          final topFields = _dashboard.getTopFieldsByProfit(limit: 5);
          final highCost = _dashboard.getHighestCostFields(limit: 5);

          if (_seasonsFuture == null) _refreshSeasons();

          return FutureBuilder<List<ProductionSeasonModel>>(
            future: _seasonsFuture,
            builder: (context, seasonSnapshot) {
              final seasons = seasonSnapshot.data ?? const <ProductionSeasonModel>[];
              return RefreshIndicator(
                onRefresh: _refreshDashboard,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Tổng quan hôm nay', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Trung tâm điều hành đất, sản xuất và tài chính của AGRICO.'),
                    const SizedBox(height: 16),
                    _QuickActions(onOpen: _open, fields: fields),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.55,
                      children: [
                        _KpiCard(icon: Icons.landscape, title: 'Diện tích', value: '${areaHa.toStringAsFixed(2)} ha'),
                        _KpiCard(icon: Icons.grid_view, title: 'Số thửa', value: '${fields.length}'),
                        _KpiCard(icon: Icons.agriculture, title: 'Vụ sản xuất', value: '${seasons.length}'),
                        _KpiCard(icon: Icons.trending_up, title: 'Doanh thu', value: _money(revenue)),
                        _KpiCard(icon: Icons.trending_down, title: 'Chi phí', value: _money(cost)),
                        _KpiCard(icon: Icons.account_balance_wallet, title: 'Lợi nhuận', value: _money(profit)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (seasonSnapshot.connectionState == ConnectionState.waiting)
                      const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())))
                    else if (seasonSnapshot.hasError)
                      Card(child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('Không tải được dữ liệu vụ sản xuất'), subtitle: Text('${seasonSnapshot.error}')))
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
                          _FinanceMetric(label: 'Doanh thu', value: _money(revenue), icon: Icons.arrow_upward),
                          _FinanceMetric(label: 'Tổng chi phí', value: _money(cost), icon: Icons.arrow_downward),
                          _FinanceMetric(label: 'Lợi nhuận', value: _money(profit), icon: Icons.account_balance_wallet),
                          _FinanceMetric(label: 'Chi phí bình quân/ha', value: _money(averageCostPerHa), icon: Icons.price_check),
                          _FinanceMetric(label: 'Biên lợi nhuận', value: '${(margin * 100).toStringAsFixed(1)}%', icon: Icons.percent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '🌱 Cơ cấu diện tích cây trồng',
                      child: crops.isEmpty
                          ? const Text('Chưa có dữ liệu thửa đất.')
                          : Column(children: crops.entries.map((e) => _ProgressRow(label: e.key, value: e.value, total: areaHa)).toList()),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '🚜 Trạng thái sản xuất',
                      child: statuses.isEmpty
                          ? const Text('Chưa có dữ liệu.')
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: statuses.entries.map((e) => Chip(avatar: const Icon(Icons.circle, size: 12), label: Text('${e.key}: ${e.value}'))).toList(),
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
                          : Column(children: topFields.map((row) => _FieldFinanceRow(row: row, onTap: () => _openField(row['fieldId'] as String))).toList()),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: '⚠️ Thửa có chi phí/ha cao',
                      child: highCost.isEmpty
                          ? const Text('Chưa có dữ liệu chi phí.')
                          : Column(children: highCost.map((row) => _FieldCostRow(row: row, onTap: () => _openField(row['fieldId'] as String))).toList()),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('⚡ Trung tâm thao tác', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ActionButton(icon: Icons.grid_view, label: 'Danh sách thửa', onTap: () => onOpen(const FieldListScreen())),
            _ActionButton(icon: Icons.insights, label: 'Hiệu quả thửa', onTap: () => onOpen(const FieldPerformanceScreen())),
            _ActionButton(icon: Icons.analytics_outlined, label: 'Phân tích chi phí', onTap: () => onOpen(CostAnalysisScreen(fields: fields))),
            _ActionButton(icon: Icons.map, label: 'Bản đồ tổng thể', onTap: () => onOpen(const OverallFieldMapScreen())),
            _ActionButton(icon: Icons.assessment, label: 'Báo cáo', onTap: () => onOpen(const ReportScreen())),
          ]),
        ]),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label));
}

class _KpiCard extends StatelessWidget {
  final IconData icon; final String title; final String value;
  const _KpiCard({required this.icon, required this.title, required this.value});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 25, color: Colors.green), const SizedBox(height: 6), Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 2), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]));
}

class _FinanceMetric extends StatelessWidget {
  final String label; final String value; final IconData icon;
  const _FinanceMetric({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: CircleAvatar(radius: 17, child: Icon(icon, size: 17)), title: Text(label), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)));
}

class _SectionCard extends StatelessWidget {
  final String title; final Widget child; final Widget? trailing;
  const _SectionCard({required this.title, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))), if (trailing != null) trailing!]), const SizedBox(height: 12), child]));
}

class _ProgressRow extends StatelessWidget {
  final String label; final double value; final double total;
  const _ProgressRow({required this.label, required this.value, required this.total});
  @override
  Widget build(BuildContext context) { final ratio = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0; return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(label)), Text('${value.toStringAsFixed(2)} ha')]), const SizedBox(height: 5), LinearProgressIndicator(value: ratio)])); }
}

class _FieldFinanceRow extends StatelessWidget {
  final Map<String, dynamic> row; final VoidCallback onTap;
  const _FieldFinanceRow({required this.row, required this.onTap});
  @override
  Widget build(BuildContext context) { final profit = (row['profit'] as num).toDouble(); final perHa = (row['profitPerHa'] as num).toDouble(); final name = row['field'] as String; return ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0] : '?')), title: Text(name), subtitle: Text('${(row['areaHa'] as num).toStringAsFixed(2)} ha • LN/ha: ${perHa.toStringAsFixed(0)} đ'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('${profit.toStringAsFixed(0)} đ', style: TextStyle(fontWeight: FontWeight.bold, color: profit >= 0 ? Colors.green : Colors.red)), const SizedBox(width: 4), const Icon(Icons.chevron_right, size: 18)]), onTap: onTap); }
}

class _FieldCostRow extends StatelessWidget {
  final Map<String, dynamic> row; final VoidCallback onTap;
  const _FieldCostRow({required this.row, required this.onTap});
  @override
  Widget build(BuildContext context) { final cost = (row['costPerHa'] as num).toDouble(); return ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange), title: Text(row['field'] as String), subtitle: Text('${(row['areaHa'] as num).toStringAsFixed(2)} ha'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('${cost.toStringAsFixed(0)} đ/ha', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 4), const Icon(Icons.chevron_right, size: 18)]), onTap: onTap); }
}
