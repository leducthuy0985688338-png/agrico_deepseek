import 'package:sqflite/sqflite.dart';

import '../../../../core/identity/data/sqlite_parcel_number_sequence.dart';
import '../../application/create_household.dart';
import '../../domain/entities/land_survey.dart';
import '../local/sqlite_land_survey_repository.dart';

class SqliteHouseholdCreationTransaction implements HouseholdCreationTransaction {
  const SqliteHouseholdCreationTransaction(this.database);

  final Database database;

  @override
  Future<Household> create({
    required String farmId,
    required Household Function(String code) build,
  }) => database.transaction((tx) => SqliteParcelNumberSequence()
      .saveHousehold(tx: tx, farmId: farmId, save: (code) async {
        final household = build(code);
        if (household.farmId != farmId || household.householdCode != code) {
          throw StateError('Household allocation scope changed.');
        }
        await SqliteLandSurveyRepository.transactionScope(tx)
            .createHousehold(household);
        return household;
      }));
}
