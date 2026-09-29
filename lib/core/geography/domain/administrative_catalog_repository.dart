import 'entities/administrative_unit.dart';

abstract interface class AdministrativeCatalogRepository {
  Future<List<AdministrativeUnit>> all();
  Future<void> add(AdministrativeUnit unit);
}
