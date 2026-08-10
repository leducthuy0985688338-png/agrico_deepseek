import 'package:flutter/foundation.dart';

import '../models/production_season_model.dart';
import '../services/production_season_database.dart';

class ProductionSeasonProvider extends ChangeNotifier {
  final ProductionSeasonDatabase _database;
  final Map<String, List<ProductionSeasonModel>> _byField = {};
  bool _loading = false;

  ProductionSeasonProvider({ProductionSeasonDatabase? database})
      : _database = database ?? ProductionSeasonDatabase();

  bool get isLoading => _loading;

  List<ProductionSeasonModel> seasonsForField(String fieldId) =>
      List.unmodifiable(_byField[fieldId] ?? const []);

  List<ProductionSeasonModel> get allSeasons => List.unmodifiable(
        _byField.values.expand((items) => items),
      );

  Future<void> loadForFields(Iterable<String> fieldIds) async {
    final ids = fieldIds.toSet();
    _loading = true;
    notifyListeners();
    try {
      final entries = await Future.wait(
        ids.map((fieldId) async => MapEntry(fieldId, await _database.getByField(fieldId))),
      );
      for (final entry in entries) {
        _byField[entry.key] = entry.value;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadForField(String fieldId) async {
    _loading = true;
    notifyListeners();
    try {
      _byField[fieldId] = await _database.getByField(fieldId);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save(ProductionSeasonModel season) async {
    await _database.upsert(season);
    final current = [...seasonsForField(season.fieldId)];
    final index = current.indexWhere((item) => item.id == season.id);
    if (index == -1) {
      current.insert(0, season);
    } else {
      current[index] = season;
    }
    _byField[season.fieldId] = current;
    notifyListeners();
  }

  Future<void> delete(ProductionSeasonModel season) async {
    await _database.delete(season.id);
    final current = seasonsForField(season.fieldId)
        .where((item) => item.id != season.id)
        .toList(growable: false);
    _byField[season.fieldId] = current;
    notifyListeners();
  }
}
