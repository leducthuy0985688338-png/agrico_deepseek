import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../services/farm_cost_alert_service.dart';

class FarmCostCauseAnalysisCard extends StatefulWidget {
  final List<FieldModel> fields;
  final List<ProductionSeasonModel> seasons;

  const FarmCostCauseAnalysisCard({
    super.key,
    required this.fields,
    required this.seasons,
  });

  @override
  State<FarmCostCauseAnalysisCard> createState() => _FarmCostCauseAnalysisCardState();
}

class _FarmCostCauseAnalysisCardState extends State<FarmCostCauseAnalysisCard> {
  late Future<List<FarmCostAlertRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant FarmCostCauseAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields || oldWidget.seasons != widget.seasons) {
      _future = _load();
    }
  }

  Future<List<FarmCostAlertRow>> _load() {
    return FarmCostAlertService().load(
      fields: widget.fields,
      seasons: widget.seasons,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FarmCostAlertRow>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Không tải được phân tích nguyên nhân chi phí'),
              subtitle: Text('${snapshot.error}'),
            ),
          );
        }

        final rows = snapshot.data ?? const <FarmCostAlertRow>[];
        final overRows = rows.where((row) => row.isOverBudget).toList();
        final causes = _calculateCauses(overRows);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      causes.isEmpty ? Icons.check_circle : Icons.rule,
                      color: causes.isEmpty ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Nguyên nhân & kiểm soát chi phí',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Làm mới',
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                Text(
                  '${overRows.length}/${rows.length} vụ vượt mức tham chiếu',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (causes.isEmpty)
                  const Text('Chưa phát hiện nhóm chi phí nổi trội cần xử lý.'),
                ...causes.take(4).map(_causeRow),
                if (causes.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Ưu tiên kiểm soát: ${causes.first.category.label}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(_controlAdvice(causes.first.category)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<_CostCause> _calculateCauses(List<FarmCostAlertRow> rows) {
    final actual = <ProductionCostCategory, double>{};
    final benchmark = <ProductionCostCategory, double>{};

    for (final row in rows) {
      final ratio = row.benchmarkTotal > 0 ? row.actualTotal / row.benchmarkTotal : 1.0;
      for (final category in ProductionCostCategory.values) {
        final amount = row.actualByCategory[category] ?? 0;
        actual[category] = (actual[category] ?? 0) + amount;
        benchmark[category] = (benchmark[category] ?? 0) + amount / ratio;
      }
    }

    final causes = ProductionCostCategory.values
        .map(
          (category) => _CostCause(
            category: category,
            actual: actual[category] ?? 0,
            benchmark: benchmark[category] ?? 0,
          ),
        )
        .where((item) => item.variance > 0)
        .toList()
      ..sort((a, b) => b.variance.compareTo(a.variance));
    return causes;
  }

  Widget _causeRow(_CostCause item) {
    final ratio = item.benchmark > 0 ? item.actual / item.benchmark : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.category.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '+${_money(item.variance)}',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: (ratio / 2).clamp(0.0, 1.0).toDouble()),
          const SizedBox(height: 3),
          Text(
            'Thực tế ${_money(item.actual)} • Tham chiếu ${_money(item.benchmark)} • ${(ratio * 100).toStringAsFixed(0)}%',
          ),
        ],
      ),
    );
  }

  String _controlAdvice(ProductionCostCategory category) {
    switch (category) {
      case ProductionCostCategory.material:
        return 'Rà soát đơn giá mua, hao hụt vật tư và định mức sử dụng trên từng ha.';
      case ProductionCostCategory.labor:
        return 'Đối chiếu ngày công với khối lượng thực tế, hạn chế tăng ca và bố trí nhân lực theo khu vực.';
      case ProductionCostCategory.machine:
        return 'Đối chiếu giờ máy với diện tích thực hiện, giảm thời gian chạy rỗng và gom lịch vận hành.';
      case ProductionCostCategory.fuel:
        return 'Đối chiếu nhiên liệu với giờ máy và diện tích; kiểm tra các điểm tiêu hao bất thường.';
    }
  }

  String _money(double value) => '${value.toStringAsFixed(0)} đ';
}

class _CostCause {
  final ProductionCostCategory category;
  final double actual;
  final double benchmark;

  const _CostCause({
    required this.category,
    required this.actual,
    required this.benchmark,
  });

  double get variance => actual - benchmark;
}
