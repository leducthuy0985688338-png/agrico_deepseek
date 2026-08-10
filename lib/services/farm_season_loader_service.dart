import '../models/production_season_model.dart';
import 'production_season_database.dart';

class FarmSeasonLoaderService {
  final ProductionSeasonDatabase _database;

  FarmSeasonLoaderService({ProductionSeasonDatabase? database})
      : _database = database ?? ProductionSeasonDatabase();

  Future<List<ProductionSeasonModel>> loadForFields(List<String> fieldIds) async {
    if (fieldIds.isEmpty) return const [];
    final results = await Future.wait(
      fieldIds.map(_database.getByField),
    );
    return results.expand((items) => items).toList(growable: false);
  }
}
