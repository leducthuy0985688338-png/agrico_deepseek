import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel sample(String id) => FieldModel(
  id: id,
  name: id,
  area: 1,
  crop: 'rice',
  status: 'active',
);

void main() {
  test('F3.3 RED: failed local delete must not report successful completion', () async {
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async {},
      deleteField: (_) async => throw StateError('simulated SQLite delete failure'),
    );
    addTearDown(provider.dispose);
    provider.addField(sample('A'));
    await expectLater(
      provider.deleteField('A'),
      throwsA(isA<StateError>()),
      reason: 'A failed local delete must be observable by its caller',
    );
  });

  test('F3.3 RED: failed local restore must not report successful completion', () async {
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async {},
      deleteField: (_) async {},
      replaceFields: (_) async => throw StateError('simulated SQLite replace failure'),
    );
    addTearDown(provider.dispose);
    await expectLater(
      provider.restoreFromCloud(fields: [sample('B')]),
      throwsA(isA<StateError>()),
      reason: 'A failed local restore must be observable by its caller',
    );
  });
}