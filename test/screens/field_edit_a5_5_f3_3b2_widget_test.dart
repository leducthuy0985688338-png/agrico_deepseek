import 'dart:async';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:agrico_deepseek/screens/field_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel sampleField() => FieldModel(
  id: 'widget-field',
  name: 'Before',
  area: 100,
  crop: 'Rice',
  status: 'Active',
);

Future<void> openEditor(WidgetTester tester, FieldProvider provider) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => FieldEditScreen(
                  field: sampleField(),
                  providerOverride: provider,
                ),
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  expect(find.text('LƯU THÔNG TIN'), findsOneWidget);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Tên lô / thửa'),
    'After',
  );
}

FieldProvider fakeProvider(Future<void> Function(FieldModel) save) =>
    FieldProvider.forTest(
      loadFields: () async => [sampleField()],
      saveField: save,
      deleteField: (_) async {},
      replaceFields: (_) async {},
    );

void main() {
  testWidgets('B2 widget: pending save keeps editor open and disables button', (
    tester,
  ) async {
    final started = Completer<void>();
    final gate = Completer<void>();
    var calls = 0;
    final provider = fakeProvider((_) async {
      calls++;
      started.complete();
      await gate.future;
    });
    addTearDown(provider.dispose);
    await openEditor(tester, provider);
    await tester.tap(find.text('LƯU THÔNG TIN'));
    await tester.pump();
    await started.future;
    expect(find.text('LƯU THÔNG TIN'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    await tester.tap(find.text('LƯU THÔNG TIN'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(provider.getFieldById('widget-field')?.name, 'After');
  });

  testWidgets('B2 widget: successful save pops editor with true', (
    tester,
  ) async {
    final provider = fakeProvider((_) async {});
    addTearDown(provider.dispose);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => FieldEditScreen(
                      field: sampleField(),
                      providerOverride: provider,
                    ),
                  ),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên lô / thửa'),
      'After',
    );
    await tester.tap(find.text('LƯU THÔNG TIN'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('Open editor'), findsOneWidget);
    expect(provider.getFieldById('widget-field')?.name, 'After');
  });

  testWidgets(
    'B2 widget: failed save stays open, shows error and permits retry',
    (tester) async {
      var calls = 0;
      final provider = fakeProvider((_) async {
        calls++;
        if (calls == 1) throw StateError('simulated disk failure');
      });
      addTearDown(provider.dispose);
      await openEditor(tester, provider);
      await tester.tap(find.text('LƯU THÔNG TIN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('LƯU THÔNG TIN'), findsOneWidget);
      expect(
        find.textContaining('Không thể lưu thông tin thửa đất'),
        findsOneWidget,
      );
      expect(provider.getFieldById('widget-field')?.name, 'Before');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('LƯU THÔNG TIN'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Open editor'), findsOneWidget);
      expect(provider.getFieldById('widget-field')?.name, 'After');
    },
  );
}
