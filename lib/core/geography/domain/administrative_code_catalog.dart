import 'entities/administrative_unit.dart';

/// Resolves a selected administrative identity to its catalogued code.
/// Names and translations are display data and never generate codes.
class AdministrativeCodeCatalog {
  AdministrativeCodeCatalog(List<AdministrativeUnit> units)
    : _byId = {for (final unit in units) unit.id: unit} {
    if (_byId.length != units.length) {
      throw const FormatException('Duplicate administrative identity.');
    }
    final scopedCodes = <String>{};
    for (final unit in _byId.values) {
      unit.validate();
      if (unit.code == null || unit.code!.trim().isEmpty) {
        throw const FormatException('Administrative unit needs a catalogued code.');
      }
      if (unit.level != AdministrativeLevel.country &&
          !_byId.containsKey(unit.parentId)) {
        throw const FormatException('Administrative parent is missing.');
      }
      final key = '${unit.parentId ?? ''}/${unit.level.name}/${unit.code}';
      if (!scopedCodes.add(key)) {
        throw const FormatException('Duplicate administrative code in parent scope.');
      }
    }
  }

  final Map<String, AdministrativeUnit> _byId;

  AdministrativeUnit resolve(String id, {AdministrativeLevel? level, String? parentId}) {
    final unit = _byId[id];
    if (unit == null || !unit.active ||
        (level != null && unit.level != level) ||
        (parentId != null && unit.parentId != parentId)) {
      throw const FormatException('Administrative selection is invalid.');
    }
    return unit;
  }

  String codeFor(String id, {AdministrativeLevel? level, String? parentId}) =>
      resolve(id, level: level, parentId: parentId).code!;
}
