import 'dart:async';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel field(String id, String name) =>
    FieldModel(id: id, name: name, area: 100, crop: 'rice', status: 'active');
Future<void> ready(FieldProvider provider) async {
  while (provider.isLoading) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'B3-C RED: successful restore invalidates queued Cloud deletion',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final deleted = <String>[];
      final remote = <String, FieldModel>{
        'target': field('target', 'Cloud original'),
      };
      final disk = <String, FieldModel>{
        'target': field('target', 'Local original'),
      };
      final provider = FieldProvider.forTest(
        loadFields: () async => disk.values.toList(),
        saveField: (value) async {
          disk[value.id] = value;
        },
        deleteField: (id) async {
          disk.remove(id);
        },
        replaceFields: (values) async {
          disk.clear();
          disk.addEntries(values.map((value) => MapEntry(value.id, value)));
        },
        cloudSaveField: (value) async {
          if (value.id == 'block') {
            started.complete();
            await gate.future;
          }
          remote[value.id] = value;
        },
        cloudDelete: (id) async {
          deleted.add(id);
          remote.remove(id);
        },
      );
      addTearDown(provider.dispose);
      await ready(provider);
      await provider.saveFieldLocally(field('block', 'Blocking Cloud save'));
      await started.future;
      await provider.deleteField('target');
      expect(disk.containsKey('target'), isFalse);
      expect(
        deleted,
        isEmpty,
        reason: 'Deletion must still be queued behind blocked save',
      );
      await provider.restoreFromCloud(fields: [remote['target']!]);
      expect(disk['target']?.name, 'Cloud original');
      gate.complete();
      await provider.cloudIdleForTest;
      expect(provider.getFieldById('target')?.name, 'Cloud original');
      expect(
        deleted,
        isEmpty,
        reason:
            'An obsolete queued delete must not erase a successfully restored field',
      );
      expect(remote['target']?.name, 'Cloud original');
    },
  );

  test('B3-C control: deletion without restore still reaches Cloud', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final deleted = <String>[];
    final provider = FieldProvider.forTest(
      loadFields: () async => [field('target', 'Before')],
      saveField: (_) async {},
      deleteField: (_) async {},
      replaceFields: (_) async {},
      cloudSaveField: (_) async {
        started.complete();
        await gate.future;
      },
      cloudDelete: (id) async {
        deleted.add(id);
      },
    );
    addTearDown(provider.dispose);
    await ready(provider);
    await provider.saveFieldLocally(field('block', 'Blocking'));
    await started.future;
    await provider.deleteField('target');
    expect(deleted, isEmpty);
    gate.complete();
    await provider.cloudIdleForTest;
    expect(deleted, ['target']);
    expect(provider.getFieldById('target'), isNull);
  });
}
