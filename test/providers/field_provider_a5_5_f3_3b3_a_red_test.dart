import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// B3-A RED: structural contract only. Never constructs the production provider,
// opens SQLite, initializes Firebase, or starts the application.
void main() {
  late String provider;
  setUpAll(() {
    provider = File('lib/providers/field_provider.dart').readAsStringSync();
  });

  test('B3-A RED: injectable fake Cloud save for deterministic tests', () {
    expect(
      provider,
      contains('Future<void> Function(FieldModel)? _testCloudSave;'),
    );
    expect(
      provider,
      contains('Future<void> Function(FieldModel)? cloudSaveField,'),
    );
  });

  test('B3-A RED: successful local save schedules Cloud separately', () {
    expect(provider, contains('_scheduleCloudSync(field.id);'));
    expect(provider, contains('await _enqueueWrite('));
  });

  test('B3-A RED: Cloud work has its own nonblocking queue', () {
    expect(
      provider,
      contains('Future<void> _cloudTail = Future<void>.value();'),
    );
    expect(provider, contains('Future<void> _enqueueCloud('));
  });

  test('B3-A RED: Cloud save checks current field identity before sending', () {
    expect(provider, contains('_isCurrentCloudCandidate('));
  });

  test(
    'B3-A RED: measurement-only history is not triggered by metadata save',
    () {
      // This existing B2 invariant should remain GREEN during B3-A.
      final localMethod = provider
          .split('Future<void> saveFieldLocally(FieldModel field) async {')
          .last
          .split('Future<void> deleteField(')
          .first;
      expect(localMethod, isNot(contains('_recordMeasurement(')));
    },
  );
}
