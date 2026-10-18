import 'dart:convert';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/services/field_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

FieldModel boundary(String name) => FieldModel(
  id: 'boundary-field', name: name, area: 200, crop: 'Rice', status: 'Active',
  polygon: const [LatLng(16, 105), LatLng(16.001, 105), LatLng(16.001, 105.001)],
  perimeter: 80, measurementMethod: 'gps+edited', measuredAt: DateTime.utc(2026, 10, 18),
);

void main() {
  sqfliteFfiInit();
  late Database database;
  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: FieldDatabase.databaseVersion,
        onConfigure: FieldDatabase.configure, onCreate: FieldDatabase.createSchema));
    await database.insert('fields', {
      'id': 'boundary-field', 'name': 'Before', 'area': 100,
      'crop': 'Rice', 'status': 'Active', 'polygon': '[]', 'photo_paths': '[]',
      'updated_at': DateTime.utc(2026).toIso8601String(),
    });
  });
  tearDown(() async { await database.close(); });

  test('boundary and measurement commit together', () async {
    final dynamic subject = FieldDatabase();
    final dynamic measurement = await subject.saveBoundaryIn(database, boundary('After'));
    final row = (await database.query('fields')).single;
    expect(row['name'], 'After');
    expect(jsonDecode(row['polygon']! as String), hasLength(3));
    final history = (await database.query('field_measurement_history')).single;
    expect(history['id'], measurement.id);
    expect(history['area'], 200);
    expect(history['polygon'], row['polygon']);
  });

  test('history failure rolls back boundary; retry records once', () async {
    await database.execute("CREATE TRIGGER reject_history BEFORE INSERT ON field_measurement_history BEGIN SELECT RAISE(ABORT, 'simulated history failure'); END");
    final dynamic subject = FieldDatabase();
    await expectLater(subject.saveBoundaryIn(database, boundary('After')), throwsA(isA<DatabaseException>()));
    expect((await database.query('fields')).single['name'], 'Before');
    expect(await database.query('field_measurement_history'), isEmpty);
    await database.execute('DROP TRIGGER reject_history');
    await subject.saveBoundaryIn(database, boundary('After'));
    expect((await database.query('fields')).single['name'], 'After');
    expect(await database.query('field_measurement_history'), hasLength(1));
  });

  test('retrying the same measured boundary keeps one history identity', () async {
    final dynamic subject = FieldDatabase();
    final dynamic first = await subject.saveBoundaryIn(database, boundary('After'));
    final dynamic second = await subject.saveBoundaryIn(database, boundary('After'));
    expect(second.id, first.id);
    expect(second.createdAt, first.createdAt);
    expect(await database.query('field_measurement_history'), hasLength(1));
  });
  test('measured creation is atomic when history insert fails', () async {
    await database.delete('fields');
    await database.execute("CREATE TRIGGER reject_new_history BEFORE INSERT ON field_measurement_history BEGIN SELECT RAISE(ABORT, 'history failure'); END");
    final subject = FieldDatabase();
    await expectLater(subject.saveBoundaryIn(database, boundary('New'), requireExisting: false), throwsA(isA<DatabaseException>()));
    expect(await database.query('fields'), isEmpty);
    expect(await database.query('field_measurement_history'), isEmpty);
    await database.execute('DROP TRIGGER reject_new_history');
    await subject.saveBoundaryIn(database, boundary('New'), requireExisting: false);
    expect(await database.query('fields'), hasLength(1));
    expect(await database.query('field_measurement_history'), hasLength(1));
  });

  test('field delete failure restores history in the same transaction', () async {
    final subject = FieldDatabase();
    await subject.saveBoundaryIn(database, boundary('After'));
    await database.execute("CREATE TRIGGER reject_field_delete BEFORE DELETE ON fields BEGIN SELECT RAISE(ABORT, 'delete failure'); END");
    await expectLater(subject.deleteIn(database, 'boundary-field'), throwsA(isA<DatabaseException>()));
    expect(await database.query('fields'), hasLength(1));
    expect(await database.query('field_measurement_history'), hasLength(1));
  });

}
