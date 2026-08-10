import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_cost_model.dart';
import '../models/production_season_model.dart';
import '../services/cost_driver_trace_service.dart';
import '../services/farm_cost_alert_service.dart';
import '../services/season_cost_driver_analysis_service.dart';
import '../services/cost_driver_recommendation_service.dart';
import '../screens/cost_driver_trace_screen.dart';

class FarmCostCauseAnalysisCardV2 extends StatefulWidget {
  final List<FieldModel> fields;
  final List<ProductionSeasonModel> seasons;

  const FarmCostCauseAnalysisCardV2({
    super.key,
    required this.fields,
    required this.seasons,
  });

  @override
  State<FarmCostCauseAnalysisCardV2> createState() => _FarmCostCauseAnalysisCardV2State();
}

class _FarmCostCauseAnalysisCardV2State extends State<FarmCostCauseAnalysisCardV2> {
  late Future<List<_TraceTarget>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_TraceTarget>> _load() async {
    if (widget.seasons.length < 2 || widget.fields.isEmpty) {
      return const <_TraceTarget>[];
    }

    final sorted = [...widget.seasons]..sort((a, b) => b.startDate.compareTo(a.startDate));
    final current = sorted.first;
    final previous = sorted[1];
    final analysis = await const SeasonCostDriverAnalysisService().analyze(
      currentSeasonId: current.id,
      previousSeasonId: previous.id,
    );

    final recommendations = const CostDriverRecommendationService().buildRecommendations(analysis);
    final fieldNames = <String, String>{for (final field in widget.fields) field.id: field.name};
    final totals = <String, double>{};
    final drivers = <String, SeasonCostDriverChange>{};

    for (final recommendation in recommendations.take(3)) {
      final rows = await const CostDriverTraceService().trace(
        season: current,
        driver: recommendation.driver,
      );
      for (final row in rows) {
        totals[row.fieldId] = (totals[row.fieldId] ?? 0) + row.amount;
        if (row.amount > 0 && !drivers.containsKey(row.fieldId)) {
          drivers[row.fieldId] = recommendation.driver;
        }
      }
    }

    final result = totals.entries.map((entry) {
      return _TraceTarget(
        fieldId: entry.key,
        fieldName: fieldNames[entry.key] ?? entry.key,
        season: current,
        driver: drivers[entry.key],
        amount: entry.value,
      );
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return result.take(3).toList(growable: false);
  }

  void _open(_TraceTarget target) {
    final driver = target.driver;
    if (driver == null) return;
    final field = widget.fields.firstWhere(
      (item) => item.id == target.fieldId,
      orElse: () => widget.fields.first,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CostDriverTraceScreen(
          field: field,
          season: target.season,
          driver: driver,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_TraceTarget>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Đang truy nguồn chi phí...'),
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
            ),
          );
        }

        final items = snapshot.data ?? const <_TraceTarget>[];
        if (items.isEmpty) return const SizedBox.shrink();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔎 Truy nguồn khoản chi tăng mạnh',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text('Thửa → Vụ sản xuất → Cost Driver → Bản ghi chi phí'),
                const SizedBox(height: 10),
                ...items.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${entry.key + 1}')),
                    title: Text(entry.value.fieldName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${entry.value.driver?.label ?? 'Cost Driver'} • ${entry.value.season.name}\n${entry.value.amount.toStringAsFixed(0)} đ'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: entry.value.driver == null ? null : () => _open(entry.value),
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

class _TraceTarget {
  final String fieldId;
  final String fieldName;
  final ProductionSeasonModel season;
  final SeasonCostDriverChange? driver;
  final double amount;

  const _TraceTarget({
    required this.fieldId,
    required this.fieldName,
    required this.season,
    required this.driver,
    required this.amount,
  });
}
