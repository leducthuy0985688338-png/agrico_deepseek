import 'dart:async';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel field(String id, String name) => FieldModel(
  id: id,
  name: name,
  area: 1,
  crop: 'rice',
  status: 'active',
);

void main() {
  late Completer<List<FieldModel>> pending;
  late FieldProvider provider;
  late List<FieldModel> writes;
  late List<String> deletions;

  setUp(() {
    pending = Completer<List<FieldModel>>();
    writes = [];
    deletions = [];
    provider = FieldProvider.forTest(
      loadFields: () => pending.future,
      saveField: (value) async { writes.add(value); },
      deleteField: (id) async { deletions.add(id); },
    );
  });

  tearDown(() {
    if (!pending.isCompleted) pending.complete([]);
    provider.dispose();
  });

  test('F1.1 delayed load must not overwrite newly added field', () async {
    provider.addField(field('new', 'New'));
    pending.complete([field('old', 'Old')]);
    await pumpEventQueue();
    expect(provider.fields.map((f) => f.id), contains('new'));
    expect(writes.map((f) => f.id), contains('new'));
  });

  test('F1.2 delayed load must not revert updated field', () async {
    provider.addField(field('a', 'New'));
    provider.updateField(field('a', 'Updated'));
    pending.complete([field('a', 'Stale')]);
    await pumpEventQueue();
    expect(provider.getFieldById('a')?.name, 'Updated');
  });

  test('F1.3 delayed load must not resurrect deleted field', () async {
    provider.addField(field('a', 'New'));
    await provider.deleteField('a');
    pending.complete([field('a', 'Stale')]);
    await pumpEventQueue();
    expect(provider.getFieldById('a'), isNull);
    expect(deletions, contains('a'));
  });

  test('F1.4 unmodified state loads persisted fields', () async {
    pending.complete([field('old', 'Old')]);
    await pumpEventQueue();
    expect(provider.getFieldById('old')?.name, 'Old');
    expect(provider.isLoading, isFalse);
  });
}
