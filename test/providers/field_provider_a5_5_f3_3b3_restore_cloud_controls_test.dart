import 'dart:async';
import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel field(String id) =>
    FieldModel(id: id, name: id, area: 1, crop: 'rice', status: 'active');

void main() {
  for (final fails in [false, true]) {
    test(
      fails
          ? 'B3-C: failed restore must not cancel a valid queued delete'
          : 'B3-C: restoring another field must not cancel a valid queued delete',
      () async {
        final started = Completer<void>();
        final gate = Completer<void>();
        final deleted = <String>[];
        final provider = FieldProvider.forTest(
          loadFields: () async => [field('target')],
          saveField: (_) async {},
          deleteField: (_) async {},
          replaceFields: (_) async {
            if (fails) throw StateError('restore disk failure');
          },
          cloudSaveField: (_) async {
            started.complete();
            await gate.future;
          },
          cloudDelete: (id) async {
            deleted.add(id);
          },
        );
        addTearDown(provider.dispose);
        while (provider.isLoading) {
          await Future<void>.delayed(Duration.zero);
        }
        await provider.saveFieldLocally(field('block'));
        await started.future;
        await provider.deleteField('target');
        if (fails) {
          await expectLater(
            provider.restoreFromCloud(fields: [field('target')]),
            throwsStateError,
          );
        } else {
          await provider.restoreFromCloud(fields: [field('other')]);
        }
        expect(deleted, isEmpty);
        gate.complete();
        await provider.cloudIdleForTest;
        expect(deleted, ['target']);
      },
    );
  }
}
