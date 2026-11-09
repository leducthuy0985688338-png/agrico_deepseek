import 'dart:async';

import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:agrico_deepseek/screens/field_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FieldModel sample() => const FieldModel(
  id: 'b3-widget',
  name: 'Before',
  area: 100,
  crop: 'Rice',
  status: 'Active',
);

Future<void> openEditor(
  WidgetTester tester,
  FieldProvider provider,
  void Function(bool?) onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => FieldEditScreen(
                      field: sample(),
                      providerOverride: provider,
                    ),
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
}

void main() {
  testWidgets('B3-B: pending Cloud does not delay editor success', (
    tester,
  ) async {
    final gate = Completer<void>();
    var cloudStarted = false;
    FieldModel? disk;
    bool? result;
    final provider = FieldProvider.forTest(
      loadFields: () async => [sample()],
      saveField: (field) async {
        disk = field;
      },
      deleteField: (_) async {},
      cloudSaveField: (_) async {
        cloudStarted = true;
        await gate.future;
      },
    );
    addTearDown(provider.dispose);
    await openEditor(tester, provider, (value) => result = value);
    await tester.tap(find.text('LƯU THÔNG TIN'));
    await tester.pumpAndSettle();
    expect(cloudStarted, isTrue);
    expect(gate.isCompleted, isFalse);
    expect(result, isTrue);
    expect(disk?.name, 'After');
    expect(find.byType(FieldEditScreen), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    await provider.cloudIdleForTest;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'B3-B: Cloud failure after editor closes preserves local success',
    (tester) async {
      final gate = Completer<void>();
      var cloudStarted = false;
      FieldModel? disk;
      bool? result;
      final provider = FieldProvider.forTest(
        loadFields: () async => [sample()],
        saveField: (field) async {
          disk = field;
        },
        deleteField: (_) async {},
        cloudSaveField: (_) async {
          cloudStarted = true;
          await gate.future;
        },
      );
      addTearDown(provider.dispose);
      await openEditor(tester, provider, (value) => result = value);
      await tester.tap(find.text('LƯU THÔNG TIN'));
      await tester.pumpAndSettle();
      expect(cloudStarted, isTrue);
      expect(result, isTrue);
      expect(find.byType(FieldEditScreen), findsNothing);
      gate.completeError(StateError('simulated offline'));
      await tester.pumpAndSettle();
      await provider.cloudIdleForTest;
      expect(disk?.name, 'After');
      expect(provider.getFieldById('b3-widget')?.name, 'After');
      expect(result, isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'B3-B: local failure keeps editor open; retry alone sends Cloud',
    (tester) async {
      var localCalls = 0;
      final sent = <String>[];
      FieldModel? disk;
      bool? result;
      final provider = FieldProvider.forTest(
        loadFields: () async => [sample()],
        saveField: (field) async {
          localCalls++;
          if (localCalls == 1) throw StateError('simulated disk failure');
          disk = field;
        },
        deleteField: (_) async {},
        cloudSaveField: (field) async {
          sent.add(field.name);
        },
      );
      addTearDown(provider.dispose);
      await openEditor(tester, provider, (value) => result = value);
      await tester.tap(find.text('LƯU THÔNG TIN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(result, isNull);
      expect(find.byType(FieldEditScreen), findsOneWidget);
      expect(
        find.textContaining('Không thể lưu thông tin thửa đất'),
        findsOneWidget,
      );
      expect(sent, isEmpty);
      expect(disk, isNull);
      expect(provider.getFieldById('b3-widget')?.name, 'Before');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('LƯU THÔNG TIN'));
      await tester.pumpAndSettle();
      await provider.cloudIdleForTest;
      expect(localCalls, 2);
      expect(sent, ['After']);
      expect(disk?.name, 'After');
      expect(result, isTrue);
      expect(find.byType(FieldEditScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
