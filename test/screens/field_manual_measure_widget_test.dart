import 'package:agrico_deepseek/screens/field_manual_measure_screen.dart';
import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/models/distance_measurement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  testWidgets('manual save retries identical identity and entered text, geometry edit invalidates', (tester) async {
    void Function(LatLng)? tapMap;
    final attempts = <FieldModel>[];
    await tester.pumpWidget(MaterialApp(home: FieldManualMeasureScreen(
      mapBuilder: (tap, markers) { tapMap = tap; return const SizedBox.expand(); },
      saveOverride: (field) async { attempts.add(field); throw StateError('disk full'); },
    )));
    for (final p in [const LatLng(16,105), const LatLng(16.001,105), const LatLng(16.001,105.001)]) {
      tapMap!(p);
    }
    await tester.pump();
    Future<void> confirm({bool enter = false}) async {
      await tester.tap(find.text('LƯU THỬA'));
      await tester.pumpAndSettle();
      if (enter) {
        await tester.enterText(find.byType(TextField).first, 'Thửa lạc');
        await tester.enterText(find.byType(TextField).last, 'Lạc');
      } else {
        final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
        expect(fields[0].controller!.text, 'Thửa lạc');
        expect(fields[1].controller!.text, 'Lạc');
      }
      await tester.tap(find.byKey(const Key('manual-confirm-save')));
      await tester.pumpAndSettle();
    }
    await confirm(enter: true);
    await confirm();
    expect(attempts, hasLength(2));
    expect(attempts[0].id, attempts[1].id);
    expect(attempts[0].measuredAt, attempts[1].measuredAt);
    expect(attempts[1].name, 'Thửa lạc');
    expect(attempts[1].crop, 'Lạc');
    tapMap!(const LatLng(16,105.001));
    await tester.pump();
    await tester.tap(find.text('LƯU THỬA'));
    await tester.pumpAndSettle();
    expect(find.text('Thửa lạc'), findsNothing);
    await tester.tap(find.byKey(const Key('manual-confirm-save')));
    await tester.pumpAndSettle();
    expect(attempts[2].id, isNot(attempts[1].id));
    expect(attempts[2].name, isNot('Thửa lạc'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('distance mode saves via independent callback without field provider', (tester) async {
    void Function(LatLng)? tapMap;
    final saved = <DistanceMeasurement>[];
    await tester.pumpWidget(MaterialApp(home: FieldManualMeasureScreen(
      mapBuilder: (tap, markers) { tapMap = tap; return const SizedBox.expand(); },
      saveDistanceOverride: (value) async { saved.add(value); return false; },
    )));
    await tester.tap(find.text('Khoảng cách'));
    await tester.pump();
    tapMap!(const LatLng(16,105));
    tapMap!(const LatLng(16.001,105));
    await tester.pump();
    await tester.tap(find.text('LƯU PHÉP ĐO'));
    await tester.pump();
    expect(saved, hasLength(1));
    expect(saved.single.points, hasLength(2));
    expect(saved.single.totalDistance, greaterThan(0));
    expect(find.textContaining('Cloud chưa sẵn sàng'), findsOneWidget);
  });
}
