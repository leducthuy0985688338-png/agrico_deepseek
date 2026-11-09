import 'package:agrico_deepseek/core/geography/domain/administrative_code_catalog.dart';
import 'package:agrico_deepseek/core/geography/domain/entities/administrative_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AdministrativeUnit unit(String id, AdministrativeLevel level, String name,
      String code, {String? parentId}) => AdministrativeUnit(
    id: id,
    level: level,
    name: name,
    code: code,
    parentId: parentId,
    createdAt: DateTime.utc(2026),
    createdBy: 'admin',
  );

  test('name changes keep the selected administrative code', () {
    final country = unit('country-1', AdministrativeLevel.country, 'Lào', 'LA');
    final province = unit('province-1', AdministrativeLevel.province,
        'ສະຫວັນນະເຂດ', 'SVK', parentId: country.id);
    final catalog = AdministrativeCodeCatalog([country, province]);
    expect(catalog.codeFor(province.id,
        level: AdministrativeLevel.province, parentId: country.id), 'SVK');
    expect(() => catalog.codeFor(province.id, parentId: 'other'),
        throwsFormatException);
    expect(AdministrativeCodeCatalog([
      country,
      unit('province-1', AdministrativeLevel.province, 'Savannakhet', 'SVK',
          parentId: country.id),
    ]).codeFor(province.id), 'SVK');
  });

  test('missing parents and duplicate codes in one parent are rejected', () {
    final country = unit('country-1', AdministrativeLevel.country, 'Lào', 'LA');
    expect(() => AdministrativeCodeCatalog([
      unit('province-1', AdministrativeLevel.province, 'X', 'SVK',
          parentId: country.id),
    ]), throwsFormatException);
    expect(() => AdministrativeCodeCatalog([
      country,
      unit('province-1', AdministrativeLevel.province, 'X', 'SVK',
          parentId: country.id),
      unit('province-2', AdministrativeLevel.province, 'Y', 'SVK',
          parentId: country.id),
    ]), throwsFormatException);
  });
}
