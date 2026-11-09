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
  test('F2.RED: delayed first save must not overwrite newer save', () async {
    final firstStarted = Completer<void>();
    final firstRelease = Completer<void>();
    final secondStarted = Completer<void>();
    final secondRelease = Completer<void>();
    var calls = 0;
    FieldModel? persisted;

    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (field) async {
        calls++;
        final call = calls;
        if (call == 1) {
          firstStarted.complete();
          await firstRelease.future;
        } else if (call == 2) {
          secondStarted.complete();
          await secondRelease.future;
        }
        persisted = field;
      },
      deleteField: (_) async {},
    );
    addTearDown(provider.dispose);

    provider.addField(makeField('first'));
    await firstStarted.future;
    provider.updateField(makeField('second'));

    // Simulate the second I/O completing before the first.
    // A serialized implementation will not start it until the first finishes.
    await Future<void>.delayed(Duration.zero);
    if (secondStarted.isCompleted) {
      secondRelease.complete();
      await pumpEventQueue();
    }
    firstRelease.complete();
    await pumpEventQueue();
    if (!secondRelease.isCompleted) {
      secondRelease.complete();
      await pumpEventQueue();
    }

    expect(provider.getFieldById('parcel-a')?.name, 'second');
    expect(persisted?.name, 'second',
        reason: 'The newest user edit must be the final persisted value');
  });
}