import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../services/season_cost_driver_analysis_service.dart';
import '../services/cost_driver_recommendation_service.dart';
import '../services/cost_driver_trace_service.dart';
import '../screens/cost_driver_trace_screen.dart';

class CostTraceEntryPoint extends StatelessWidget {
  final List<FieldModel> fields;
  final List<ProductionSeasonModel> seasons;

  const CostTraceEntryPoint({super.key, required this.fields, required this.seasons});

  Future<List<_Target>> _load() async {
    if (fields.isEmpty || seasons.length < 2) return const <_Target>[];
    final sorted = [...seasons]..sort((a, b) => b.startDate.compareTo(a.startDate));
    final current = sorted.first;
    final analysis = await const SeasonCostDriverAnalysisService().analyze(
      currentSeasonId: current.id,
      previousSeasonId: sorted[1].id,
    );
    final recommendations = const CostDriverRecommendationService().buildRecommendations(analysis);
    final names = <String, String>{for (final field in fields) field.id: field.name};
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

    final result = totals.entries.map((entry) => _Target(
      fieldId: entry.key,
      fieldName: names[entry.key] ?? entry.key,
      season: current,
      driver: drivers[entry.key],
      amount: entry.value,
    )).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return result.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Target>>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
        }
        final items = snapshot.data ?? const <_Target>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('🔎 Truy nguồn khoản chi tăng mạnh', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Thửa → Vụ sản xuất → Cost Driver → Bản ghi chi phí'),
              ),
              ...items.asMap().entries.map((entry) {
                final target = entry.value;
                final driver = target.driver;
                return ListTile(
                  leading: CircleAvatar(child: Text('${entry.key + 1}')),
                  title: Text(target.fieldName),
                  subtitle: Text('${driver?.label ?? 'Cost Driver'} • ${target.season.name}\n${target.amount.toStringAsFixed(0)} đ'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: driver == null ? null : () {
                    final field = fields.firstWhere((item) => item.id == target.fieldId, orElse: () => fields.first);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CostDriverTraceScreen(field: field, season: target.season, driver: driver)));
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _Target {
  final String fieldId;
  final String fieldName;
  final ProductionSeasonModel season;
  final SeasonCostDriverChange? driver;
  final double amount;

  const _Target({required this.fieldId, required this.fieldName, required this.season, required this.driver, required this.amount});
}
