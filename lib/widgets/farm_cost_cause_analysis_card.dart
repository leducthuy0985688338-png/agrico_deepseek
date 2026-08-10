import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../services/cost_driver_recommendation_service.dart';
import '../services/cost_driver_trace_service.dart';
import '../services/season_cost_driver_analysis_service.dart';
import '../screens/cost_driver_trace_screen.dart';

class FarmCostCauseAnalysisCard extends StatefulWidget {
  final List<FieldModel> fields;
  final List<ProductionSeasonModel> seasons;

  const FarmCostCauseAnalysisCard({
    super.key,
    required this.fields,
    required this.seasons,
  });

  @override
  State<FarmCostCauseAnalysisCard> createState() =>
      _FarmCostCauseAnalysisCardState();
}

class _FarmCostCauseAnalysisCardState
    extends State<FarmCostCauseAnalysisCard> {
  late Future<_AnalysisResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant FarmCostCauseAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fields != widget.fields ||
        oldWidget.seasons != widget.seasons) {
      _future = _load();
    }
  }

  Future<_AnalysisResult> _load() async {
    if (widget.seasons.length < 2 || widget.fields.isEmpty) {
      return const _AnalysisResult.empty();
    }

    final sorted = [...widget.seasons]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final current = sorted.first;
    final previous = sorted.firstWhere(
      (season) => season.id != current.id,
      orElse: () => sorted[1],
    );

    final analysis = await const SeasonCostDriverAnalysisService().analyze(
      currentSeasonId: current.id,
      previousSeasonId: previous.id,
    );
    final recommendations =
        const CostDriverRecommendationService().buildRecommendations(analysis);

    final fieldNames = <String, String>{
      for (final field in widget.fields) field.id: field.name,
    };
    final totals = <String, double>{};
    final drivers = <String, SeasonCostDriverChange>{};

    for (final recommendation in recommendations.take(3)) {
      final rows = await const CostDriverTraceService().trace(
        season: current,
        driver: recommendation.driver,
      );
      for (final row in rows) {
        totals[row.fieldId] = (totals[row.fieldId] ?? 0) + row.amount;
        drivers.putIfAbsent(row.fieldId, () => recommendation.driver);
      }
    }

    final sources = totals.entries
        .map(
          (entry) => _TopCostSource(
            fieldId: entry.key,
            fieldName: fieldNames[entry.key] ?? entry.key,
            amount: entry.value,
            driver: drivers[entry.key],
          ),
        )
        .where((item) => item.driver != null && item.amount > 0)
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return _AnalysisResult(
      season: current,
      recommendations: recommendations.take(3).toList(growable: false),
      sources: sources.take(3).toList(growable: false),
    );
  }

  void _reload() {
    setState(() => _future = _load());
  }

  void _openTrace(_AnalysisResult result, _TopCostSource source) {
    final driver = source.driver;
    if (driver == null) return;

    final field = widget.fields.cast<FieldModel?>().firstWhere(
          (item) => item?.id == source.fieldId,
          orElse: () => null,
        );
    if (field == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CostDriverTraceScreen(
          field: field,
          season: result.season!,
          driver: driver,
        ),
      ),
    );
  }

  String _money(double value) => '${value.toStringAsFixed(0)} đ';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AnalysisResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Đang phân tích và truy nguồn chi phí...'),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Không tải được truy nguồn chi phí'),
              subtitle: Text('${snapshot.error}'),
              trailing: IconButton(
                tooltip: 'Thử lại',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ),
          );
        }

        final result = snapshot.data ?? const _AnalysisResult.empty();
        if (result.season == null) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.analytics_outlined),
              title: Text('Truy nguồn chi phí'),
              subtitle: Text('Cần ít nhất 2 vụ sản xuất để so sánh cost driver.'),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_tree, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Truy nguồn nguyên nhân chi phí',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Làm mới',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                Text(
                  'Vụ hiện tại: ${result.season!.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (result.recommendations.isEmpty)
                  const Text('Chưa đủ dữ liệu để xác định cost driver tăng mạnh.')
                else ...[
                  const Text(
                    '🎯 Cost Driver cần kiểm soát',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...result.recommendations.map(
                    (item) => _RecommendationRow(
                      recommendation: item,
                      money: _money,
                    ),
                  ),
                ],
                const Divider(height: 28),
                const Text(
                  '📍 Top thửa gây tăng chi phí',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (result.sources.isEmpty)
                  const Text('Chưa xác định được thửa chi phí tăng.')
                else
                  ...result.sources.asMap().entries.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text('${entry.key + 1}'),
                      ),
                      title: Text(
                        entry.value.fieldName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${entry.value.driver!.label} • ${entry.value.driver!.category.label}\nNguồn tăng: ${_money(entry.value.amount)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openTrace(result, entry.value),
                    ),
                  ),
                if (result.sources.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Chạm vào một thửa để đi thẳng tới các bản ghi chi phí.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  final CostDriverRecommendation recommendation;
  final String Function(double) money;

  const _RecommendationRow({
    required this.recommendation,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(recommendation.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.35)),
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
                        recommendation.driver.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '+${money(recommendation.absoluteChange)}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${recommendation.driver.category.label} • tăng ${(recommendation.changeRate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(recommendation.action),
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

class _TopCostSource {
  final String fieldId;
  final String fieldName;
  final double amount;
  final SeasonCostDriverChange? driver;

  const _TopCostSource({
    required this.fieldId,
    required this.fieldName,
    required this.amount,
    required this.driver,
  });
}

class _AnalysisResult {
  final ProductionSeasonModel? season;
  final List<CostDriverRecommendation> recommendations;
  final List<_TopCostSource> sources;

  const _AnalysisResult({
    required this.season,
    required this.recommendations,
    required this.sources,
  });

  const _AnalysisResult.empty()
      : season = null,
        recommendations = const <CostDriverRecommendation>[],
        sources = const <_TopCostSource>[];
}
