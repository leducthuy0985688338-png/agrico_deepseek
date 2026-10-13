import 'package:agrico_deepseek/features/finance/application/finance_document_filter.dart';
import 'package:agrico_deepseek/features/finance/application/finance_v2_report.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'finance_filtered_export_test.dart' as fixture;

class _Store implements FinanceDocumentStore {
  int reads = 0;
  List<FinanceDocument> items = [
    fixture.document('lak'),
    fixture.document('vnd', currency: 'VND'),
    fixture.document('usd', currency: 'USD'),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'currency filters workbook documents totals and export scope without conversion',
    () async {
      final store = _Store();
      final workbook = await FinanceV2Report(store).workbook(
        'farm-a',
        filter: const FinanceDocumentFilter(currency: 'VND'),
      );
      expect(workbook['Finance V2'].rows, hasLength(2));
      expect(
        (workbook['Finance V2'].rows[1][3]!.value as TextCellValue).value
            .toString(),
        'VND',
      );
      expect(workbook['Totals V2'].rows, hasLength(2));
      expect(
        (workbook['Totals V2'].rows[1][2]!.value as IntCellValue).value,
        1000000,
      );
      final scope = workbook['Filter V2'].rows.singleWhere(
        (row) =>
            (row[0]!.value as TextCellValue).value.toString() == 'Currency',
      );
      expect((scope[1]!.value as TextCellValue).value.toString(), 'VND');
      expect(store.reads, 1);
    },
  );
  test(
    'all and persisted other currencies are supported, empty codes reject before reads',
    () async {
      final store = _Store();
      expect(
        (await FinanceV2Report(store).workbook('farm-a'))['Finance V2'].rows,
        hasLength(4),
      );
      expect(
        (await FinanceV2Report(store).workbook(
          'farm-a',
          filter: const FinanceDocumentFilter(currency: 'USD'),
        ))['Finance V2'].rows,
        hasLength(2),
      );
      final before = store.reads;
      await expectLater(
        FinanceV2Report(store).workbook(
          'farm-a',
          filter: const FinanceDocumentFilter(currency: '   '),
        ),
        throwsFormatException,
      );
      expect(store.reads, before);
      store.items.add(
        fixture.document('foreign', farm: 'other', currency: 'LAK'),
      );
      await expectLater(
        FinanceV2Report(store).workbook(
          'farm-a',
          filter: const FinanceDocumentFilter(currency: 'VND'),
        ),
        throwsStateError,
      );
    },
  );
}
