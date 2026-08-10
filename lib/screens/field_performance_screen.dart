import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/dashboard_provider.dart';
import '../providers/field_provider.dart';
import 'field_detail_screen.dart';

class FieldPerformanceScreen extends StatefulWidget {
  const FieldPerformanceScreen({super.key});

  @override
  State<FieldPerformanceScreen> createState() => _FieldPerformanceScreenState();
}

class _FieldPerformanceScreenState extends State<FieldPerformanceScreen> {
  int _mode = 0;

  String _money(num value) {
    final amount = value.toDouble();
    if (amount.abs() >= 1000000000) return '${(amount / 1000000000).toStringAsFixed(2)} tỷ';
    if (amount.abs() >= 1000000) return '${(amount / 1000000).toStringAsFixed(2)} triệu';
    return '${amount.toStringAsFixed(0)} đ';
  }

  List<Map<String, dynamic>> _rows(DashboardProvider dashboard) {
    final rows = dashboard.getTopFieldsByProfit(limit: 999999).toList();
    rows.sort((a, b) {
      switch (_mode) {
        case 1:
          return (b['costPerHa'] as num).compareTo(a['costPerHa'] as num);
        case 2:
          final aArea = (a['areaHa'] as num).toDouble();
          final bArea = (b['areaHa'] as num).toDouble();
          final aRevenuePerHa = aArea > 0 ? (a['revenue'] as num).toDouble() / aArea : 0.0;
          final bRevenuePerHa = bArea > 0 ? (b['revenue'] as num).toDouble() / bArea : 0.0;
          return bRevenuePerHa.compareTo(aRevenuePerHa);
        default:
          return (b['profitPerHa'] as num).compareTo(a['profitPerHa'] as num);
      }
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final fields = context.watch<FieldProvider>();
    final rows = _rows(dashboard);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hiệu quả từng thửa'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '🏆 Xếp hạng hiệu quả sản xuất',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text('Chạm vào một thửa để mở hồ sơ đầy đủ: bản đồ, vụ sản xuất, chi phí, thu hoạch và lợi nhuận.'),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Lợi nhuận/ha'), icon: Icon(Icons.trending_up)),
                ButtonSegment(value: 1, label: Text('Chi phí/ha'), icon: Icon(Icons.warning_amber)),
                ButtonSegment(value: 2, label: Text('Doanh thu/ha'), icon: Icon(Icons.payments)),
              ],
              selected: {_mode},
              onSelectionChanged: (value) => setState(() => _mode = value.first),
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Chưa có dữ liệu tài chính theo thửa.'),
                ),
              )
            else
              ...rows.asMap().entries.map((entry) {
                final index = entry.key;
                final row = entry.value;
                final fieldId = row['fieldId'] as String;
                final field = fields.getFieldById(fieldId);
                final areaHa = (row['areaHa'] as num).toDouble();
                final profit = (row['profit'] as num).toDouble();
                final cost = (row['cost'] as num).toDouble();
                final profitPerHa = (row['profitPerHa'] as num).toDouble();
                final costPerHa = (row['costPerHa'] as num).toDouble();
                final revenue = (row['revenue'] as num).toDouble();
                final revenuePerHa = areaHa > 0 ? revenue / areaHa : 0.0;
                final metric = _mode == 1 ? costPerHa : (_mode == 2 ? revenuePerHa : profitPerHa);
                final isNegative = _mode == 0 && profit < 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    isThreeLine: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: CircleAvatar(
                      child: Text(index < 3 ? ['🥇', '🥈', '🥉'][index] : '${index + 1}'),
                    ),
                    title: Text(
                      row['field'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${areaHa.toStringAsFixed(2)} ha\n'
                      'LN: ${_money(profit)} • CP: ${_money(cost)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _money(metric),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isNegative ? Colors.red : Colors.green,
                          ),
                        ),
                        Text(
                          _mode == 1 ? 'đ/ha' : (_mode == 2 ? 'DT/ha' : 'LN/ha'),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                    onTap: field == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => FieldDetailScreen(field: field)),
                            ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            Card(
              color: Colors.blueGrey.withValues(alpha: 0.08),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  '💡 Mẹo: mở một thửa để đi tiếp vào vụ sản xuất. Từ đó có thể xem nhật ký, thu hoạch, máy móc và các chỉ số hiệu quả của thửa.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
