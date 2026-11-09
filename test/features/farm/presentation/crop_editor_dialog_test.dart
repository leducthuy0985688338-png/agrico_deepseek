import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/presentation/widgets/crop_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CropRecord original() => CropRecord(
    id: 'crop-1',
    parcelId: 'plot',
    cropType: 'Peanut',
    quantity: 12,
    unit: 'plants',
    variety: 'L14',
    plantingDate: DateTime.utc(2026, 9, 1),
    plantingYear: 2026,
    ageMonths: 2,
    condition: CropCondition.healthy,
    notes: 'note',
    active: true,
    createdAt: DateTime.utc(2026, 9, 1),
    createdBy: 'member',
    updatedAt: DateTime.utc(2026, 9, 1),
    updatedBy: 'member',
  );
  CropRecord? result;
  Future<void> open(WidgetTester tester, {CropRecord? value}) async {
    result = null;
    await tester.binding.setSurfaceSize(const Size(480, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<CropRecord>(
                  context: context,
                  builder: (_) =>
                      CropEditorDialog(original: value, parcelId: 'plot'),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String key, String value) async {
    final field = find.byKey(Key(key));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('save-crop')));
    await tester.pumpAndSettle();
  }

  testWidgets('edit crop fields preserves identity and creation audit', (
    tester,
  ) async {
    final before = original();
    await open(tester, value: before);
    await fill(tester, 'crop-type', 'Cassava');
    await fill(tester, 'crop-variety', 'KM94');
    await fill(tester, 'crop-quantity', '24,5');
    await fill(tester, 'crop-planting-date', '2026-09-15');
    await fill(tester, 'crop-notes', 'changed');
    await save(tester);
    expect(result!.id, before.id);
    expect(result!.parcelId, 'plot');
    expect(result!.createdAt, before.createdAt);
    expect(result!.createdBy, before.createdBy);
    expect(result!.cropType, 'Cassava');
    expect(result!.variety, 'KM94');
    expect(result!.quantity, 24.5);
    expect(result!.plantingDate, DateTime.utc(2026, 9, 15));
    expect(result!.notes, 'changed');
    expect(result!.condition, CropCondition.healthy);
  });
  testWidgets('new crop accepts date and derives year when omitted', (
    tester,
  ) async {
    await open(tester);
    await fill(tester, 'crop-type', 'Peanut');
    await fill(tester, 'crop-quantity', '12');
    await fill(tester, 'crop-unit', 'plants');
    await fill(tester, 'crop-planting-date', '2026-10-02');
    await save(tester);
    expect(result!.id, startsWith('draft-'));
    expect(result!.plantingYear, 2026);
    expect(result!.parcelId, 'plot');
  });
  testWidgets('blank zero or nonnumeric quantity stays open', (tester) async {
    await open(tester, value: original());
    for (final quantity in ['', '0', 'abc', '-1']) {
      await fill(tester, 'crop-quantity', quantity);
      await save(tester);
      expect(result, isNull);
      expect(find.byKey(const Key('crop-editor-error')), findsOneWidget);
    }
  });
  testWidgets('nonexistent date and conflicting year rejected', (tester) async {
    await open(tester, value: original());
    await fill(tester, 'crop-planting-date', '2026-02-30');
    await save(tester);
    expect(result, isNull);
    expect(
      find.text('Ngày trồng phải đúng dạng YYYY-MM-DD và là ngày có thật.'),
      findsOneWidget,
    );
    await fill(tester, 'crop-planting-date', '2026-09-01');
    await fill(tester, 'crop-planting-year', '2025');
    await save(tester);
    expect(result, isNull);
    expect(find.byKey(const Key('crop-editor-error')), findsOneWidget);
  });
  testWidgets('optional variety date year and notes can be cleared', (
    tester,
  ) async {
    await open(tester, value: original());
    for (final key in [
      'crop-variety',
      'crop-planting-date',
      'crop-planting-year',
      'crop-notes',
    ]) {
      await fill(tester, key, '');
    }
    await save(tester);
    expect(result!.variety, isNull);
    expect(result!.plantingDate, isNull);
    expect(result!.plantingYear, isNull);
    expect(result!.notes, isNull);
  });
  testWidgets('condition can be changed on an existing crop', (tester) async {
    await open(tester, value: original());
    final field = find.byKey(const Key('crop-condition'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh trưởng kém').last);
    await tester.pumpAndSettle();
    await save(tester);
    expect(result!.condition, CropCondition.stressed);
  });
  testWidgets('cancel does not return a modified draft', (tester) async {
    await open(tester, value: original());
    await fill(tester, 'crop-type', 'Cassava');
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
