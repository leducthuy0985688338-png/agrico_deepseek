import 'dart:async';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel field(String id) => FieldModel(
  id: id,
  name: id,
  area: 1,
  crop: 'rice',
  status: 'active',
);

void main() {
  test('F3.2 RED: restore must be serialized after pending save', () async {
    final saveStarted = Completer<void>();
    final releaseSave = Completer<void>();
    final events = <String>[];
    final stored = <String, FieldModel>{};
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (value) async {
        events.add('save-start');
        saveStarted.complete();
        await releaseSave.future;
        stored[value.id] = value;
        events.add('save-end');
      },
      deleteField: (id) async { stored.remove(id); },
      replaceFields: (values) async {
        events.add('restore');
        stored
          ..clear()
          ..addEntries(values.map((value) => MapEntry(value.id, value)));
      },
    );
    addTearDown(provider.dispose);

    provider.addField(field('A'));
    await saveStarted.future;
    final restoring = provider.restoreFromCloud(fields: [field('B')]);
    await pumpEventQueue();
    releaseSave.complete();
    await restoring;
    await pumpEventQueue();

    expect(events, ['save-start', 'save-end', 'restore'],
        reason: 'Restore must wait for earlier pending save');
    expect(stored.keys, contains('B'));
    expect(stored.keys, isNot(contains('A')));
    expect(provider.fields.map((f) => f.id), ['B']);
  });
}