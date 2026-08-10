import 'package:flutter/material.dart';

import '../models/field_model.dart';
import '../models/production_season_model.dart';
import '../models/production_cost_model.dart';
import '../services/season_cost_driver_analysis_service.dart';

class SeasonCostDriverAnalysisScreen extends StatefulWidget {
  final FieldModel field;
  final ProductionSeasonModel currentSeason;
  final ProductionSeasonModel previousSeason;

  const SeasonCostDriverAnalysisScreen({
    super.key,
    required this.field,
    required this.currentSeason,
    required this.previousSeason,
  });

  @override
  State<SeasonCostDriverAnalysisScreen> createState() => _SeasonCostDriverAnalysisScreenState();
}

class _SeasonCostDriverAnalysisScreenState extends State<SeasonCostDriverAnalysisScreen> {
  late Future<SeasonCostDriverAnalysis> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<SeasonCostDriverAnalysis> _load() => const SeasonCostDriverAnalysisService().analyze(
        currentSeasonId: widget.currentSeason.id,
        previousSeasonId: widget.previousSeason.id,
      );

  void _reload() => setState(() => _future = _load());

  String _money(double value) => '${value.toStringAsFixed(0)} đ';

  String _percent(double value) => '${value >= 0 ? '+' : ''}${(value * 100).toStringAsFixed(1)}%';

  String _categoryLabel(ProductionCostCategory category) => category.label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phân tích biến động chi phí'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<SeasonCostDriverAnalysis>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton(onPressed: _reload, child: const Text('Thử lại')),
            );
          }
          final data = snapshot.data!;
          final drivers = [...data.increasingDrivers]
            ..sort((a, b) => b.absoluteChange.compareTo(a.absoluteChange));
          final categories = [...data.categories]
            ..sort((a, b) => b.absoluteChange.compareTo(a.absoluteChange));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.field.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${widget.currentSeason.name}  →  ${widget.previousSeason.name}'),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tổng chi phí', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(_money(data.currentTotal), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                      Text('${_money(data.totalChange)}  (${_percent(data.totalChangeRate)})'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Biến động theo nhóm', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...categories.map(
                (item) => Card(
                  child: ListTile(
                    leading: Icon(item.absoluteChange > 0 ? Icons.trending_up : Icons.trending_down),
                    title: Text(_categoryLabel(item.category)),
                    subtitle: Text('Vụ trước: ${_money(item.previousAmount)}  •  Vụ này: ${_money(item.currentAmount)}'),
                    trailing: Text(
                      '${item.absoluteChange >= 0 ? '+' : ''}${_money(item.absoluteChange)}\n${_percent(item.changeRate)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: item.absoluteChange > 0 ? Colors.orange : Colors.green,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Khoản chi tăng mạnh nhất', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (drivers.isEmpty)
                const Card(child: ListTile(title: Text('Không phát hiện khoản chi tăng.'))),
              ...drivers.take(10).map(
                (item) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(item.label),
                    subtitle: Text(_categoryLabel(item.category)),
                    trailing: Text(
                      '+${_money(item.absoluteChange)}\n${_percent(item.changeRate)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                ),
              ),
              if (drivers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '💡 Ưu tiên kiểm tra "${drivers.first.label}" trước. Đây là khoản có mức tăng tuyệt đối lớn nhất giữa hai vụ.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
