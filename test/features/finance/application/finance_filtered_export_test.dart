import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_filter.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/finance_v2_report.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'finance_parcel_link_test.dart' as fixture;

FinanceDocument document(
  String id, {
  String? parcel = 'one',
  String currency = 'LAK',
  bool receipt = false,
  String farm = 'farm-a',
  int day = 12,
}) => FinanceDocument(
  id: id,
  code: id,
  organizationId: farm,
  parcelId: parcel,
  kind: receipt ? BusinessDocumentKind.receipt : BusinessDocumentKind.payment,
  occurredAt: DateTime.utc(2026, 10, day, 23, 59),
  amountMinor: 1000000,
  currency: currency,
  category: 'Mua giống',
  description: 'ຂໍ້ມູນ',
);

class _Store implements FinanceDocumentStore {
  int reads = 0;
  void Function()? onRead;
  List<FinanceDocument> items = [
    document('one'),
    document('vnd', currency: 'VND'),
    document('receipt', receipt: true),
    document('general', parcel: null),
    document('old', day: 9),
    document('otherParcel', parcel: 'two'),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    onRead?.call();
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'filtered workbook and currency totals use one persisted read',
    () async {
      final store = _Store();
      final filter = FinanceDocumentFilter(
        query: ' ຂໍ້ມູນ ',
        kind: BusinessDocumentKind.payment,
        parcel: 'parcel:one',
        from: DateTime(2026, 10, 12),
        to: DateTime(2026, 10, 12),
      );
      final workbook = await FinanceV2Report(
        store,
      ).workbook('farm-a', filter: filter);
      expect(store.reads, 1);
      expect(workbook['Finance V2'].rows, hasLength(3));
      final totals = workbook['Totals V2'].rows;
      expect(totals, hasLength(3));
      for (final row in totals.skip(1)) {
        expect((row[1]!.value as IntCellValue).value, 0);
        expect((row[2]!.value as IntCellValue).value, 1000000);
        expect((row[3]!.value as IntCellValue).value, -1000000);
      }
      expect(
        (workbook['Filter V2'].rows.last[1]!.value as TextCellValue).value
            .toString(),
        'one',
      );
      expect(workbook.save(), isNotEmpty);
    },
  );
  test(
    'default export includes all, general and empty filters preserve valid workbook',
    () async {
      final store = _Store();
      expect(
        (await FinanceV2Report(store).workbook('farm-a'))['Finance V2'].rows,
        hasLength(7),
      );
      expect(
        (await FinanceV2Report(store).workbook(
          'farm-a',
          filter: const FinanceDocumentFilter(parcel: 'general'),
        ))['Finance V2'].rows,
        hasLength(2),
      );
      final empty = await FinanceV2Report(store).workbook(
        'farm-a',
        filter: const FinanceDocumentFilter(query: 'missing'),
      );
      expect(empty['Finance V2'].rows, hasLength(1));
      expect(empty['Totals V2'].rows, hasLength(1));
    },
  );
  test(
    'invalid filters reject before reads and filtering cannot hide foreign rows',
    () async {
      final store = _Store();
      for (final filter in [
        const FinanceDocumentFilter(parcel: 'parcel:'),
        const FinanceDocumentFilter(kind: BusinessDocumentKind.stockIn),
        FinanceDocumentFilter(
          from: DateTime(2026, 10, 13),
          to: DateTime(2026, 10, 12),
        ),
      ]) {
        await expectLater(
          FinanceV2Report(store).workbook('farm-a', filter: filter),
          throwsFormatException,
        );
      }
      expect(store.reads, 0);
      store.items.add(document('foreign', farm: 'foreign'));
      await expectLater(
        FinanceV2Report(store).workbook(
          'farm-a',
          filter: const FinanceDocumentFilter(query: 'missing'),
        ),
        throwsStateError,
      );
    },
  );
  test('revoked report permission prevents filtered file writer', () async {
    final actor = fixture.actor();
    var live = actor;
    final store = _Store();
    final service = FinanceDocumentService(
      repository: store,
      subject: actor,
      currentSubject: () => live,
    );
    // Replace the live grant with a finance-view-only identity during the read.
    store.onRead = () {
      live = AuthorizationSubject(
        userId: actor.userId,
        membershipId: actor.membershipId,
        farmId: actor.farmId,
        permissionCodes: {PermissionCodes.financeView},
        dataScopes: const {DataScope.allFarm},
        validUntil: DateTime.now().add(const Duration(hours: 1)),
      );
    };
    var writes = 0;
    await expectLater(
      service.exportReport(
        filter: const FinanceDocumentFilter(parcel: 'general'),
        save: (_) async {
          writes++;
        },
      ),
      throwsStateError,
    );
    expect(writes, 0);
  });
}
