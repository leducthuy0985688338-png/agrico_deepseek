import 'dart:async';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/screens/field_gps_measure_screen.dart';
import 'package:agrico_deepseek/services/gps_field_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position point(double latitude, double longitude) => Position(
  latitude: latitude, longitude: longitude, timestamp: DateTime.utc(2026, 10, 18),
  accuracy: 3, altitude: 0, altitudeAccuracy: 0, heading: 0,
  headingAccuracy: 0, speed: 0, speedAccuracy: 0,
);

class FakeGps extends GpsFieldService {
  final positions = StreamController<Position>(sync: true);
  @override
  Future<bool> ensureLocationReady() async => true;
  @override
  Future<Position?> getCurrentPosition() async => point(16, 105);
  @override
  Stream<Position> positionStream() => positions.stream;
}

Widget fakeMap() => const SizedBox.expand();

Future<void> openMeasurement(WidgetTester tester, Widget screen,
    void Function(FieldModel?) result) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
    builder: (context) => TextButton(
      onPressed: () async => result(await Navigator.of(context).push<FieldModel>(
        MaterialPageRoute(builder: (_) => screen),
      )),
      child: const Text('Open GPS'),
    ),
  ))));
  await tester.tap(find.text('Open GPS'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('BẮT ĐẦU ĐO GPS'));
  await tester.pumpAndSettle();
  final gps = (screen as FieldGpsMeasureScreen).gpsOverride! as FakeGps;
  addTearDown(gps.positions.close);
  gps.positions.add(point(16.001, 105));
  gps.positions.add(point(16.001, 105.001));
  await tester.pump();
  expect(find.textContaining('3 điểm'), findsOneWidget);
  final stop = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'DỪNG ĐO'),
  ).onPressed! as Future<void> Function();
  await tester.runAsync(stop);
  await tester.pumpAndSettle();
  expect(find.text('BẮT ĐẦU ĐO GPS'), findsOneWidget);
}

Future<void> confirmMeasurement(WidgetTester tester) async {
  expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == 'Lưu thửa')).onPressed, isNotNull);
  await tester.tap(find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == 'Lưu thửa'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lưu thửa').last);
  await tester.pump();
}

void main() {
  testWidgets('draft returns measured geometry without legacy persistence', (tester) async {
    FieldModel? result;
    await openMeasurement(tester, FieldGpsMeasureScreen.draft(
      gpsOverride: FakeGps(), mapBuilder: fakeMap,
    ), (value) => result = value);
    await confirmMeasurement(tester);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.polygon, hasLength(3));
    expect(result!.area, greaterThan(1));
    expect(result!.measurementMethod, 'gps');
    expect(result!.measuredAt, isNotNull);
    expect(find.byType(FieldGpsMeasureScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled draft returns no measurement', (tester) async {
    FieldModel? result;
    await openMeasurement(tester, FieldGpsMeasureScreen.draft(
      gpsOverride: FakeGps(), mapBuilder: fakeMap,
    ), (value) => result = value);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == 'Lưu thửa')).onPressed, isNotNull);
  await tester.tap(find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == 'Lưu thửa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(FieldGpsMeasureScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('legacy GPS still waits for local persistence', (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    FieldModel? result;
    await openMeasurement(tester, FieldGpsMeasureScreen(
      gpsOverride: FakeGps(), mapBuilder: fakeMap,
      saveOverride: (_) { calls++; return gate.future; },
    ), (value) => result = value);
    await confirmMeasurement(tester);
    expect(calls, 1);
    expect(result, isNull);
    expect(find.byType(FieldGpsMeasureScreen), findsOneWidget);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == 'Lưu thửa')).onPressed, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(find.byType(FieldGpsMeasureScreen), findsNothing);
  });

  testWidgets('legacy GPS persistence failure keeps measurement open', (tester) async {
    FieldModel? result;
    await openMeasurement(tester, FieldGpsMeasureScreen(
      gpsOverride: FakeGps(), mapBuilder: fakeMap,
      saveOverride: (_) async => throw StateError('disk full'),
    ), (value) => result = value);
    await confirmMeasurement(tester);
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(FieldGpsMeasureScreen), findsOneWidget);
    expect(find.textContaining('Không thể lưu thửa'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
      widget is IconButton && widget.tooltip == 'Lưu thửa')).onPressed, isNotNull);
  });
}
