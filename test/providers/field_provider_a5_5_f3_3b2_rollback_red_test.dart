import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel field(String name) => FieldModel(
  id: 'f3b2',
  name: name,
  area: 100,
  crop: 'rice',
  status: 'active',
);

void main() {
  test('F3.3-B2 RED: failed local edit must not leave unsaved value visible', () async {
    final provider = FieldProvider.forTest(
      loadFields: () async => [field('before')],
      saveField: (_) async => throw StateError('disk failure'),
      deleteField: (_) async {},
      replaceFields: (_) async {},
    );
    addTearDown(provider.dispose);
    // Let the asynchronous fake load finish before the edit.
    while (provider.isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(provider.getFieldById('f3b2')?.name, 'before');
    await expectLater(
      provider.saveFieldLocally(field('after')),
      throwsA(isA<StateError>()),
    );
    expect(provider.getFieldById('f3b2')?.name, 'before',
        reason: 'An uncommitted edit must not masquerade as saved data');
  });
}