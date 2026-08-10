import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../services/cost_driver_recommendation_service.dart';
import '../services/cost_driver_trace_service.dart';
import '../services/farm_cost_alert_service.dart';
import '../services/season_cost_driver_analysis_service.dart';

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
  late Future<List<CostDriverRecommendation>> _recommendationsFuture;
  late Future<List<_TopCostSource>> _topSourcesFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant FarmCostCauseAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields || oldWidget.seasons != widget.seasons) {
      _reload();
    }
  }

  void _reload() {
    _future = _load();
    _recommendationsFuture = _loadRecommendations();
    _topSourcesFuture = _loadTopSources();
  }

  Future<List<FarmCostAlertRow>> _load() {
    return FarmCostAlertService().load(
      fields: widget.fields,
      seasons: widget.seasons,
    );
  }

  Future<SeasonCostDriverAnalysis?> _loadAnalysis() async {
    if (widget.seasons.length < 2) return null;

    final sorted = [...widget.seasons]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final current = sorted.first;
    final previous = sorted.firstWhere(
      (season) => season.id != current.id,
      orElse: () => sorted[1],
    );

    return const SeasonCostDriverAnalysisService().analyze(
      currentSeasonId: current.id,
      previousSeasonId: previous.id,
    );
  }

  Future<List<CostDriverRecommendation>> _loadRecommendations() async {
    final analysis = await _loadAnalysis();
    if (analysis == null) return const <CostDriverRecommendation>[];
    return const CostDriverRecommendationService().buildRecommendations(analysis);
  }

  Future<List<_TopCostSource>> _loadTopSources() async {
    if (widget.seasons.length < 2 || widget.fields.isEmpty) {
      return const <_TopCostSource>[];
    }

    final sorted = [...widget.seasons]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final current = sorted.first;
    final recommendations = await _loadRecommendations();
    if (recommendations.isEmpty) return const <_TopCostSource>[];

    final fieldNames = <String, String>{
      for (final field in widget.fields) field.id: field.name,
    };
    final totals = <String, double>{};
    final drivers = <String, Set<String>>{};

    for (final recommendation in recommendations.take(3)) {
      final rows = await const CostDriverTraceService().trace(
        season: current,
        driver: recommendation.driver,
      );
      for (final row in rows) {
        totals[row.fieldId] = (totals[row.fieldId] ?? 0) + row.amount;
        drivers.putIfAbsent(row.fieldId, () => <String>{}).add(row.driverLabel);
      }
    }

    final result = totals.entries
        .map(
          (entry) => _TopCostSource(
            fieldId: entry.key,
            fieldName: fieldNames[entry.key] ?? entry.key,
            amount: entry.value,
            drivers: (drivers[entry.key] ?? const <String>{}).toList(growable: false),
          ),
        )
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return result.take(3).toList(growable: false);
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
                      onPressed: () => setState(_reload),
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
                const Divider(height: 24),
                _RecommendationSection(future: _recommendationsFuture),
                const Divider(height: 24),
                _TopCostSourcesSection(future: _topSourcesFuture),
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

class _RecommendationSection extends StatelessWidget {
  final Future<List<CostDriverRecommendation>> future;

  const _RecommendationSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CostDriverRecommendation>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Đang phân tích cost driver...'),
            ],
          );
        }
        if (snapshot.hasError) {
          return Text('Không tải được khuyến nghị: ${snapshot.error}');
        }

        final items = snapshot.data ?? const <CostDriverRecommendation>[];
        if (items.isEmpty) {
          return const Text('Chưa đủ dữ liệu để so sánh cost driver giữa các vụ.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎯 Khuyến nghị theo Cost Driver',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.take(3).map((item) => _recommendationRow(item)),
          ],
        );
      },
    );
  }

  Widget _recommendationRow(CostDriverRecommendation item) {
    final color = _levelColor(item.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.driver.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '+${item.absoluteChange.toStringAsFixed(0)} đ',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.driver.category.label} • tăng ${(item.changeRate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(item.action),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(CostRecommendationLevel level) {
    switch (level) {
      case CostRecommendationLevel.low:
        return Colors.green;
      case CostRecommendationLevel.medium:
        return Colors.amber.shade800;
      case CostRecommendationLevel.high:
        return Colors.deepOrange;
      case CostRecommendationLevel.critical:
        return Colors.red;
    }
  }
}

class _TopCostSourcesSection extends StatelessWidget {
  final Future<List<_TopCostSource>> future;

  const _TopCostSourcesSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_TopCostSource>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Đang truy nguồn chi phí theo thửa...'),
            ],
          );
        }
        if (snapshot.hasError) {
          return Text('Không tải được nguồn chi phí: ${snapshot.error}');
        }

        final items = snapshot.data ?? const <_TopCostSource>[];
        if (items.isEmpty) {
          return const Text('Chưa có đủ dữ liệu để xác định thửa gây tăng chi phí.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📍 Top thửa gây tăng chi phí',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.asMap().entries.map(
              (entry) => _topCostSourceRow(context, entry.key + 1, entry.value),
            ),
          ],
        );
      },
    );
  }

  Widget _topCostSourceRow(BuildContext context, int rank, _TopCostSource item) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      title: Text(item.fieldName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${item.drivers.isEmpty ? 'Cost driver' : item.drivers.join(' • ')}\nNguồn tăng: ${item.amount.toStringAsFixed(0)} đ',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: item.onTap,
    );
  }
}

class _TopCostSource {
  final String fieldId;
  final String fieldName;
  final double amount;
  final List<String> drivers;
  VoidCallback? onTap;

  _TopCostSource({
    required this.fieldId,
    required this.fieldName,
    required this.amount,
    required this.drivers,
  });
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
