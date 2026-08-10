import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../services/cost_budget_service.dart';
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
  late Future<_FarmCostCauseAnalysis> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant FarmCostCauseAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields || oldWidget.seasons != widget.seasons) {
      setState(() => _future = _load());
    }
  }

  Future<_FarmCostCauseAnalysis> _load() async {
    final budgets = await CostBudgetService().load();
    final rows = await FarmCostAlertService().load(
      fields: widget.fields,
      seasons: widget.seasons,
    );

    final categoryActual = <ProductionCostCategory, double>{};
    final categoryBudget = <ProductionCostCategory, double>{};
    final overRows = rows.where((row) => row.isOverBudget).toList();

    for (final row in rows) {
      for (final category in ProductionCostCategory.values) {
        categoryActual[category] =
            (categoryActual[category] ?? 0) + (row.actualByCategory[category] ?? 0);
        categoryBudget[category] =
            (categoryBudget[category] ?? 0) +
                (budgets[category] ?? 0) * row.areaHa;
      }
    }

    final causes = ProductionCostCategory.values
        .map(
          (category) => _CostCause(
            category: category,
            actual: categoryActual[category] ?? 0,
            budget: categoryBudget[category] ?? 0,
          ),
        )
        .where((item) => item.variance > 0)
        .toList()
      ..sort((a, b) => b.variance.compareTo(a.variance));

    return _FarmCostCauseAnalysis(
      rows: rows,
      overRows: overRows,
      causes: causes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FarmCostCauseAnalysis>(
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

        final data = snapshot.data!;
        final critical = data.overRows.where((row) => row.isCritical).length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      data.causes.isEmpty ? Icons.check_circle : Icons.rule,
                      color: data.causes.isEmpty ? Colors.green : Colors.orange,
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
                  '${data.overRows.length}/${data.rows.length} vụ vượt định mức • $critical vụ ở mức nguy cơ',
                  style: TextStyle(
                    color: critical > 0 ? Colors.red : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (data.causes.isEmpty)
                  const Text('Chưa phát hiện nhóm chi phí vượt định mức.'),
                ...data.causes.take(4).map(_causeRow),
                if (data.causes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                  Text(
                    'Ưu tiên cắt/kiểm soát: ${data.causes.first.category.label}.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(_controlAdvice(data.causes.first.category)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _causeRow(_CostCause item) {
    final ratio = item.budget > 0 ? item.actual / item.budget : 0.0;
    final progress = ratio.clamp(0.0, 2.0).toDouble() / 2;
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
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: progress)),
              const SizedBox(width: 8),
              Text('${(ratio * 100).toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 3),
          Text('Thực tế ${_money(item.actual)} • Định mức ${_money(item.budget)}'),
        ],
      ),
    );
  }

  String _controlAdvice(ProductionCostCategory category) {
    switch (category) {
      case ProductionCostCategory.material:
        return 'Rà soát đơn giá mua, hao hụt vật tư và định mức sử dụng/ha; ưu tiên đối chiếu nhập kho với nhật ký sản xuất.';
      case ProductionCostCategory.labor:
        return 'Kiểm tra ngày công theo thửa, năng suất lao động và phần tăng ca; điều phối nhân lực theo khối lượng thực tế.';
      case ProductionCostCategory.machine:
        return 'Đối chiếu giờ máy với diện tích thực hiện, hạn chế chạy rỗng và gom lịch vận hành theo khu vực.';
      case ProductionCostCategory.fuel:
        return 'Đối chiếu nhiên liệu với giờ máy và diện tích; kiểm tra mức tiêu hao bất thường và cấp phát theo định mức.';
    }
  }

  String _money(double value) => '${value.toStringAsFixed(0)} đ';
}

class _FarmCostCauseAnalysis {
  final List<FarmCostAlertRow> rows;
  final List<FarmCostAlertRow> overRows;
  final List<_CostCause> causes;

  const _FarmCostCauseAnalysis({
    required this.rows,
    required this.overRows,
    required this.causes,
  });
}

class _CostCause {
  final ProductionCostCategory category;
  final double actual;
  final double budget;

  const _CostCause({
    required this.category,
    required this.actual,
    required this.budget,
  });

  double get variance => actual - budget;
}
