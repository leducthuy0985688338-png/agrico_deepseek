import 'dart:async';
import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel field(String name, {String id = 'f'}) =>
    FieldModel(id: id, name: name, area: 100, crop: 'rice', status: 'active');
Future<void> ready(FieldProvider p) async {
  while (p.isLoading) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('local failure never calls Cloud', () async {
    final sent = <String>[];
    final p = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async => throw StateError('disk'),
      deleteField: (_) async {},
      cloudSaveField: (f) async {
        sent.add(f.name);
      },
    );
    addTearDown(p.dispose);
    await ready(p);
    await expectLater(p.saveFieldLocally(field('A')), throwsStateError);
    await p.cloudIdleForTest;
    expect(sent, isEmpty);
    expect(p.fields, isEmpty);
  });
  test('Cloud starts only after local success', () async {
    final disk = Completer<void>();
    final started = Completer<void>();
    final sent = <String>[];
    final p = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async {
        started.complete();
        await disk.future;
      },
      deleteField: (_) async {},
      cloudSaveField: (f) async {
        sent.add(f.name);
      },
    );
    addTearDown(p.dispose);
    await ready(p);
    final save = p.saveFieldLocally(field('A'));
    await started.future;
    expect(sent, isEmpty);
    disk.complete();
    await save;
    await p.cloudIdleForTest;
    expect(sent, ['A']);
  });
  test(
    'pending Cloud does not block next SQLite save; A finishes before B',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final local = <String>[];
      final remote = <String>[];
      final p = FieldProvider.forTest(
        loadFields: () async => [],
        saveField: (f) async {
          local.add(f.name);
        },
        deleteField: (_) async {},
        cloudSaveField: (f) async {
          if (f.name == 'A') {
            started.complete();
            await gate.future;
          }
          remote.add(f.name);
        },
      );
      addTearDown(p.dispose);
      await ready(p);
      await p.saveFieldLocally(field('A'));
      await started.future;
      await p.saveFieldLocally(field('B')).timeout(const Duration(seconds: 2));
      expect(local, ['A', 'B']);
      expect(remote, isEmpty);
      gate.complete();
      await p.cloudIdleForTest;
      expect(remote, ['A', 'B']);
    },
  );
  test('Cloud error retains local value and queue continues', () async {
    final sent = <String>[];
    final p = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async {},
      deleteField: (_) async {},
      cloudSaveField: (f) async {
        if (f.name == 'A') throw StateError('offline');
        sent.add(f.name);
      },
    );
    addTearDown(p.dispose);
    await ready(p);
    await p.saveFieldLocally(field('A'));
    await p.cloudIdleForTest;
    expect(p.getFieldById('f')?.name, 'A');
    await p.saveFieldLocally(field('B'));
    await p.cloudIdleForTest;
    expect(sent, ['B']);
  });
  test('queued old candidate is skipped after newer edit', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final sent = <String>[];
    final p = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async {},
      deleteField: (_) async {},
      cloudSaveField: (f) async {
        if (f.id == 'block') {
          started.complete();
          await gate.future;
        }
        sent.add(f.name);
      },
    );
    addTearDown(p.dispose);
    await ready(p);
    await p.saveFieldLocally(field('block', id: 'block'));
    await started.future;
    await p.saveFieldLocally(field('A'));
    await p.saveFieldLocally(field('B'));
    gate.complete();
    await p.cloudIdleForTest;
    expect(sent, ['block', 'B']);
  });
  test('queued save is skipped when field has been deleted', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final events = <String>[];
    final p = FieldProvider.forTest(
      loadFields: () async => [],
      saveField: (_) async {},
      deleteField: (_) async {},
      cloudSaveField: (f) async {
        if (f.id == 'block') {
          started.complete();
          await gate.future;
        }
        events.add('save:${f.id}');
      },
      cloudDelete: (id) async {
        events.add('delete:$id');
      },
    );
    addTearDown(p.dispose);
    await ready(p);
    await p.saveFieldLocally(field('block', id: 'block'));
    await started.future;
    await p.saveFieldLocally(field('A'));
    await p.deleteField('f');
    gate.complete();
    await p.cloudIdleForTest;
    expect(events, ['save:block', 'delete:f']);
    expect(p.getFieldById('f'), isNull);
  });
  test(
    'in-flight save completes before Cloud deletion; SQLite deletion is not blocked',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final events = <String>[];
      final p = FieldProvider.forTest(
        loadFields: () async => [],
        saveField: (_) async {},
        deleteField: (_) async {
          events.add('local-delete');
        },
        cloudSaveField: (_) async {
          started.complete();
          await gate.future;
          events.add('cloud-save');
        },
        cloudDelete: (_) async {
          events.add('cloud-delete');
        },
      );
      addTearDown(p.dispose);
      await ready(p);
      await p.saveFieldLocally(field('A'));
      await started.future;
      await p.deleteField('f').timeout(const Duration(seconds: 2));
      expect(events, ['local-delete']);
      gate.complete();
      await p.cloudIdleForTest;
      expect(events, ['local-delete', 'cloud-save', 'cloud-delete']);
    },
  );
  test('legacy update local failure does not send Cloud', () async {
    final sent = <String>[];
    final disk = Completer<void>();
    final p = FieldProvider.forTest(
      loadFields: () async => [field('before')],
      saveField: (_) async {
        disk.complete();
        throw StateError('disk');
      },
      deleteField: (_) async {},
      cloudSaveField: (f) async {
        sent.add(f.name);
      },
    );
    addTearDown(p.dispose);
    await ready(p);
    p.updateField(field('after'));
    await disk.future;
    await Future<void>.delayed(Duration.zero);
    await p.cloudIdleForTest;
    expect(sent, isEmpty);
  });
}
