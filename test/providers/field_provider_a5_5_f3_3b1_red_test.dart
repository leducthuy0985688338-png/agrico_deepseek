import 'dart:async';

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
  test('F3.3-B1 RED: caller can await successful local save', () async {
    final saved = <String>[];
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (field) async { saved.add(field.id); },
      deleteField: (_) async {},
      replaceFields: (_) async {},
    );
    addTearDown(provider.dispose);

    // dynamic allows the RED test to compile before the API exists.
    final dynamic subject = provider;
    await subject.saveFieldLocally(sample('B1'));
    expect(saved, ['B1']);
  });

  test('F3.3-B1 RED: failed local save reaches awaiting caller', () async {
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async => throw StateError('simulated local write failure'),
      deleteField: (_) async {},
      replaceFields: (_) async {},
    );
    addTearDown(provider.dispose);

    final dynamic subject = provider;
    await expectLater(
      subject.saveFieldLocally(sample('B2')),
      throwsA(isA<StateError>()),
    );
  });

  test('F3.3-B1 RED: awaited local save retains write queue ordering', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final events = <String>[];
    final provider = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (field) async {
        events.add('save-start');
        started.complete();
        await gate.future;
        events.add('save-end');
      },
      deleteField: (_) async { events.add('delete'); },
      replaceFields: (_) async {},
    );
    addTearDown(provider.dispose);
    final dynamic subject = provider;
    final Future<void> save = subject.saveFieldLocally(sample('B3'));
    await started.future;
    final deletion = provider.deleteField('B3');
    expect(events, ['save-start']);
    gate.complete();
    await Future.wait([save, deletion]);
    expect(events, ['save-start', 'save-end', 'delete']);
  });
}
