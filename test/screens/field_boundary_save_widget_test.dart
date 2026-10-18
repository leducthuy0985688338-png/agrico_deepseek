import 'dart:async';

import 'package:agrico_deepseek/models/field_measurement_history.dart';
import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:agrico_deepseek/screens/field_polygon_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

FieldModel sample() => const FieldModel(id: 'boundary', name: 'Before',
  crop: 'Rice', status: 'Active', area: 100, measurementMethod: 'gps',
  polygon: [LatLng(16, 105), LatLng(16.001, 105), LatLng(16.001, 105.001)]);
FieldMeasurementHistory measurement(FieldModel field) => FieldMeasurementHistory(
  id: 'history-${field.measuredAt!.microsecondsSinceEpoch}', fieldId: field.id,
  fieldName: field.name, measurementMethod: field.measurementMethod,
  polygon: field.polygon, area: field.area, perimeter: field.perimeter,
  measuredAt: field.measuredAt!, createdAt: field.measuredAt!);
Future<void> openEditor(WidgetTester tester, FieldProvider provider,
    void Function(FieldModel?) result,
    {Widget Function(Set<Marker>, Set<Polygon>)? mapBuilder}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
    builder: (context) => TextButton(onPressed: () async {
      result(await Navigator.of(context).push<FieldModel>(MaterialPageRoute(
        builder: (_) => FieldPolygonEditScreen(field: sample(),
          providerOverride: provider, mapBuilder: mapBuilder ?? (_, _) => const SizedBox()),
      )));
    }, child: const Text('Open')),
  ))));
  await tester.tap(find.text('Open')); await tester.pumpAndSettle();
}

void main() {
  testWidgets('pending atomic write keeps editor open and locks both save buttons', (tester) async {
    final gate = Completer<void>(); var calls = 0;
    final saved = <FieldModel>[];
    Set<Marker> markers = {};
    final provider = FieldProvider.forTest(loadFields: () async => [sample()],
      saveField: (_) async {}, deleteField: (_) async {},
      saveBoundary: (field) async { calls++; saved.add(field); await gate.future; return measurement(field); });
    addTearDown(provider.dispose);
    FieldModel? result;
    await openEditor(tester, provider, (value) => result = value,
      mapBuilder: (value, _) { markers = value; return const SizedBox(); });
    await tester.tap(find.text('LƯU RANH GIỚI MỚI')); await tester.pump();
    expect(calls, 1); expect(result, isNull);
    expect(find.byType(FieldPolygonEditScreen), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byTooltip('Lưu thay đổi')).onPressed, isNull);
    markers.first.onDragEnd!(const LatLng(17, 106));
    await tester.tap(find.text('LƯU RANH GIỚI MỚI'), warnIfMissed: false); await tester.pump();
    expect(calls, 1);
    gate.complete(); await tester.pumpAndSettle(); await provider.cloudIdleForTest;
    expect(result, isNotNull); expect(result!.polygon, saved.single.polygon);
    expect(result!.polygon.first, sample().polygon.first);
    expect(find.byType(FieldPolygonEditScreen), findsNothing);
  });

  testWidgets('atomic failure keeps editor open; retry reuses measurement date', (tester) async {
    final snapshots = <FieldModel>[]; final sent = <String>[];
    final provider = FieldProvider.forTest(loadFields: () async => [sample()],
      saveField: (_) async {}, deleteField: (_) async {},
      saveBoundary: (field) async { snapshots.add(field); if (snapshots.length == 1) throw StateError('disk'); return measurement(field); },
      cloudSaveField: (field) async { sent.add(field.id); });
    addTearDown(provider.dispose);
    FieldModel? result;
    await openEditor(tester, provider, (value) => result = value);
    await tester.tap(find.text('LƯU RANH GIỚI MỚI')); await tester.pumpAndSettle();
    expect(result, isNull); expect(sent, isEmpty);
    expect(provider.getFieldById('boundary')?.area, 100);
    expect(find.textContaining('Không thể lưu ranh giới'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await tester.tap(find.text('LƯU RANH GIỚI MỚI')); await tester.pumpAndSettle(); await provider.cloudIdleForTest;
    expect(snapshots, hasLength(2)); expect(snapshots[0].measuredAt, snapshots[1].measuredAt);
    expect(result, isNotNull); expect(sent, ['boundary']);
  });

  testWidgets('Cloud measurement failure does not reverse boundary success', (tester) async {
    var measurementCalls = 0;
    final provider = FieldProvider.forTest(loadFields: () async => [sample()],
      saveField: (_) async {}, deleteField: (_) async {},
      saveBoundary: (field) async => measurement(field),
      cloudMeasurement: (_) async { measurementCalls++; throw StateError('offline'); });
    addTearDown(provider.dispose);
    FieldModel? result;
    await openEditor(tester, provider, (value) => result = value);
    await tester.tap(find.text('LƯU RANH GIỚI MỚI')); await tester.pumpAndSettle(); await provider.cloudIdleForTest;
    expect(result, isNotNull); expect(measurementCalls, 1);
    expect(find.byType(FieldPolygonEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('boundary save preserves metadata edited since editor was opened', () async {
    FieldModel? persisted;
    final provider = FieldProvider.forTest(loadFields: () async => [sample().copyWith(name: 'New name', crop: 'Peanut')],
      saveField: (_) async {}, deleteField: (_) async {},
      saveBoundary: (field) async { persisted = field; return measurement(field); });
    addTearDown(provider.dispose);
    while (provider.isLoading) { await Future<void>.delayed(Duration.zero); }
    await provider.saveBoundaryLocally(sample().copyWith(measuredAt: DateTime.utc(2026, 10, 18)));
    await provider.cloudIdleForTest;
    expect(persisted?.name, 'New name'); expect(persisted?.crop, 'Peanut');
  });
}
