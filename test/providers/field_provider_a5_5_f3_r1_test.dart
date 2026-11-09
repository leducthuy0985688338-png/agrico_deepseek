import 'dart:async';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel makeField(String name) => FieldModel(
  id: 'parcel-a',
  name: name,
  area: 1,
  crop: 'rice',
  status: 'active',
);

void main() {
  test('F3.1 save in flight then delete does not resurrect field', () async {
    final saveStarted = Completer<void>();
    final releaseSave = Completer<void>();
    final events = <String>[];
    final stored = <String, FieldModel>{};
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (field) async {
        events.add('save-start');
        saveStarted.complete();
        await releaseSave.future;
        stored[field.id] = field;
        events.add('save-end');
      },
      deleteField: (id) async {
        events.add('delete');
        stored.remove(id);
      },
    );
    addTearDown(provider.dispose);

    provider.addField(makeField('first'));
    await saveStarted.future;
    final deleting = provider.deleteField('parcel-a');
    await Future<void>.delayed(Duration.zero);
    expect(events, ['save-start'], reason: 'delete must wait for save');
    releaseSave.complete();
    await deleting;
    expect(events, ['save-start', 'save-end', 'delete']);
    expect(stored.containsKey('parcel-a'), isFalse);
    expect(provider.getFieldById('parcel-a'), isNull);
  });

  test('F3.2 failed save must not block following delete', () async {
    final events = <String>[];
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (field) async {
        events.add('save-failed');
        throw StateError('simulated write failure');
      },
      deleteField: (id) async { events.add('delete'); },
    );
    addTearDown(provider.dispose);
    provider.addField(makeField('first'));
    await provider.deleteField('parcel-a');
    expect(events, ['save-failed', 'delete']);
    expect(provider.getFieldById('parcel-a'), isNull);
  });
}