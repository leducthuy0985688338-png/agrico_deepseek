import 'package:flutter/material.dart';

import '../providers/dashboard_provider.dart';
import '../providers/field_provider.dart';

class FarmDashboardScreen extends StatefulWidget {
  const FarmDashboardScreen({super.key});

  @override
  State<FarmDashboardScreen> createState() => _FarmDashboardScreenState();
}

class _FarmDashboardScreenState extends State<FarmDashboardScreen> {
  final DashboardProvider _dashboard = DashboardProvider();
  final FieldProvider _fields = FieldProvider();

  @override
  void dispose() {
    _dashboard.dispose();
    super.dispose();
  }

  String _money(num value) {
    final amount = value.toDouble();
    if (amount.abs() >= 1000000000) return '${(amount / 1000000000).toStringAsFixed(2)} tỷ';
    if (amount.abs() >= 1000000) return '${(amount / 1000000).toStringAsFixed(2)} triệu';
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
            onPressed: () => setState(() {}),
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
          final topFields = _dashboard.getTopFieldsByProfit(limit: 5);
          final highCost = _dashboard.getHighestCostFields(limit: 5);

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Tổng quan hôm nay', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Toàn bộ chỉ số đất, sản xuất và tài chính trên một màn hình.'),
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
                    _KpiCard(icon: Icons.trending_up, title: 'Doanh thu', value: _money(revenue)),
                    _KpiCard(icon: Icons.trending_down, title: 'Chi phí', value: _money(cost)),
                    _KpiCard(icon: Icons.account_balance_wallet, title: 'Lợi nhuận', value: _money(profit)),
                    _KpiCard(icon: Icons.agriculture, title: 'Máy móc', value: '${_dashboard.totalMachines}'),
                  ],
                ),
                const SizedBox(height: 20),
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
                          children: statuses.entries
                              .map((e) => Chip(avatar: const Icon(Icons.circle, size: 12), label: Text('${e.key}: ${e.value}')))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: '💰 Hiệu quả theo thửa',
                  child: topFields.isEmpty
                      ? const Text('Chưa có báo cáo tài chính theo thửa.')
                      : Column(children: topFields.map((row) => _FieldFinanceRow(row: row)).toList()),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: '⚠️ Thửa có chi phí/ha cao',
                  child: highCost.isEmpty
                      ? const Text('Chưa có dữ liệu chi phí.')
                      : Column(children: highCost.map((row) => _FieldCostRow(row: row)).toList()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _KpiCard({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 25, color: Colors.green),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ]),
      ),
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
    final ratio = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(label)), Text('${value.toStringAsFixed(2)} ha')]),
        const SizedBox(height: 5),
        LinearProgressIndicator(value: ratio),
      ]),
    );
  }
}

class _FieldFinanceRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _FieldFinanceRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final profit = (row['profit'] as num).toDouble();
    final perHa = (row['profitPerHa'] as num).toDouble();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text('${(row['field'] as String).isNotEmpty ? (row['field'] as String)[0] : '?'}')),
      title: Text(row['field'] as String),
      subtitle: Text('${(row['areaHa'] as num).toStringAsFixed(2)} ha • LN/ha: ${perHa.toStringAsFixed(0)} đ'),
      trailing: Text('${profit.toStringAsFixed(0)} đ', style: TextStyle(fontWeight: FontWeight.bold, color: profit >= 0 ? Colors.green : Colors.red)),
    );
  }
}

class _FieldCostRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _FieldCostRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final cost = (row['costPerHa'] as num).toDouble();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: Text(row['field'] as String),
      subtitle: Text('${(row['areaHa'] as num).toStringAsFixed(2)} ha'),
      trailing: Text('${cost.toStringAsFixed(0)} đ/ha', style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
