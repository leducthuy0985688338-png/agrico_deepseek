import 'package:flutter/foundation.dart';

import '../models/production_log_model.dart';
import '../services/production_log_database.dart';

class ProductionLogProvider extends ChangeNotifier {
  final ProductionLogDatabase _database;
  final Map<String, List<ProductionLogModel>> _logs = {};
  bool _loading = false;

  ProductionLogProvider({ProductionLogDatabase? database}) : _database = database ?? ProductionLogDatabase();

  bool get isLoading => _loading;
  List<ProductionLogModel> logsForSeason(String seasonId) => List.unmodifiable(_logs[seasonId] ?? const []);
  List<ProductionLogModel> get allLogs => List.unmodifiable(_logs.values.expand((items) => items));

  Future<void> loadForSeasons(Iterable<String> seasonIds) async {
    final ids = seasonIds.toSet();
    _loading = true;
    notifyListeners();
    try {
      final entries = await Future.wait(
        ids.map((seasonId) async => MapEntry(seasonId, await _database.getBySeason(seasonId))),
      );
      for (final entry in entries) {
        _logs[entry.key] = entry.value;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadForSeason(String seasonId) async {
    _loading = true;
    notifyListeners();
    try {
      _logs[seasonId] = await _database.getBySeason(seasonId);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save(ProductionLogModel log) async {
    await _database.upsert(log);
    final current = [...logsForSeason(log.seasonId)];
    final index = current.indexWhere((item) => item.id == log.id);
    if (index == -1) current.insert(0, log); else current[index] = log;
    current.sort((a, b) => b.date.compareTo(a.date));
    _logs[log.seasonId] = current;
    notifyListeners();
  }

  Future<void> delete(ProductionLogModel log) async {
    await _database.delete(log.id);
    _logs[log.seasonId] = logsForSeason(log.seasonId).where((item) => item.id != log.id).toList(growable: false);
    notifyListeners();
  }

  double totalCost(String seasonId) => logsForSeason(seasonId).fold(0, (sum, item) => sum + item.cost);
}
