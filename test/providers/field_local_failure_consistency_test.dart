import 'dart:async';
import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/models/field_measurement_history.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
FieldModel field(String id, String name) => FieldModel(id: id, name: name, area: 100, crop: 'Rice', status: 'Active');
Future<void> ready(FieldProvider p) async { while (p.isLoading) { await Future<void>.delayed(Duration.zero); } }
void main() {
  test('failed save rolls back even if another field was edited meanwhile', () async {
    final gate = Completer<void>(); final started = Completer<void>();
    final p = FieldProvider.forTest(loadFields: () async => [field('a', 'Before'), field('b', 'Before')],
      saveField: (f) async { if (f.id == 'a') { started.complete(); await gate.future; throw StateError('disk'); } },
      deleteField: (_) async {});
    addTearDown(p.dispose); await ready(p);
    final failed = expectLater(p.saveFieldLocally(field('a', 'Unsaved')), throwsStateError);
    await started.future;
    final other = p.saveFieldLocally(field('b', 'Saved'));
    gate.complete(); await failed; await other; await p.cloudIdleForTest;
    expect(p.getFieldById('a')?.name, 'Before'); expect(p.getFieldById('b')?.name, 'Saved');
  });
  test('failed deletion restores field and does not call Cloud', () async {
    final deleted = <String>[];
    final p = FieldProvider.forTest(loadFields: () async => [field('a', 'Before')],
      saveField: (_) async {}, deleteField: (_) async => throw StateError('disk'),
      cloudDelete: (id) async { deleted.add(id); });
    addTearDown(p.dispose); await ready(p);
    await expectLater(p.deleteField('a'), throwsStateError); await p.cloudIdleForTest;
    expect(p.getFieldById('a')?.name, 'Before'); expect(deleted, isEmpty);
  });
  test('failed restore rolls back its fields while preserving a newer edit', () async {
    final started = Completer<void>(); final gate = Completer<void>();
    final p = FieldProvider.forTest(loadFields: () async => [field('a', 'Original A'), field('b', 'Original B')],
      saveField: (_) async {}, deleteField: (_) async {},
      replaceFields: (_) async { started.complete(); await gate.future; throw StateError('restore'); });
    addTearDown(p.dispose); await ready(p);
    final failure = expectLater(p.restoreFromCloud(fields: [field('a', 'Remote A'), field('new', 'Remote new')]), throwsStateError);
    await started.future;
    final edit = p.saveFieldLocally(field('a', 'New edit'));
    gate.complete(); await failure; await edit; await p.cloudIdleForTest;
    expect(p.getFieldById('a')?.name, 'New edit'); expect(p.getFieldById('b')?.name, 'Original B');
    expect(p.getFieldById('new'), isNull);
  });
  test('failed photo save rolls back without writing measurement history', () async {
    var measurements = 0;
    final p = FieldProvider.forTest(loadFields: () async => [field('a', 'Before')],
      saveField: (_) async => throw StateError('disk'), deleteField: (_) async {},
      cloudMeasurement: (_) async { measurements++; });
    addTearDown(p.dispose); await ready(p);
    await expectLater(p.saveFieldPhotosLocally('a', ['photo.jpg']), throwsStateError);
    await p.cloudIdleForTest;
    expect(p.getFieldById('a')?.photoPaths, isEmpty); expect(measurements, 0);
  });
  test('measured create uses one atomic callback and syncs after success', () async {
    final events = <String>[];
    final measured = field('new', 'New').copyWith(polygon: const [LatLng(16,105),LatLng(16.001,105),LatLng(16.001,105.001)],
      measurementMethod: 'gps', measuredAt: DateTime.utc(2026,10,18));
    final p = FieldProvider.forTest(loadFields: () async => [],
      saveField: (_) async { fail('Measured create must not use the plain field writer'); }, deleteField: (_) async {},
      saveBoundary: (f) async {
        events.add('atomic');
        return FieldMeasurementHistory(id: 'history',fieldId:f.id,fieldName:f.name,
          measurementMethod:f.measurementMethod,polygon:f.polygon,area:f.area,perimeter:f.perimeter,
          measuredAt:f.measuredAt!,createdAt:f.measuredAt!);
      }, cloudSaveField: (_) async { events.add('field-cloud'); },
      cloudMeasurement: (_) async { events.add('history-cloud'); });
    addTearDown(p.dispose); await ready(p);
    await p.createMeasuredFieldLocally(measured); await p.cloudIdleForTest;
    expect(events, ['atomic','field-cloud','history-cloud']); expect(p.getFieldById('new'), measured);
  });
}
