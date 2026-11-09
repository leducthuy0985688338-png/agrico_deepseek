import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/finance_parcel_link_test.dart' as parcels;
import 'finance_document_details_test.dart' as fixture;

FinanceDocument document(
  String id,
  String? parcelId, {
  bool receipt = false,
  bool old = false,
}) => FinanceDocument(
  id: id,
  organizationId: 'farm-a',
  code: id,
  parcelId: parcelId,
  kind: receipt ? BusinessDocumentKind.receipt : BusinessDocumentKind.payment,
  occurredAt: DateTime(2026, old ? 9 : 10, 12),
  amountMinor: 1000000,
  currency: 'LAK',
  category: 'Mua giống',
  description: 'ຂໍ້ມູນ',
);

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [
    document('general', null),
    document('one', 'one'),
    document('two', 'historic'),
    document('receipt', 'one', receipt: true),
    document('old', 'one', old: true),
  ];
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async => List.of(items);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Parcels implements LandParcelRepository {
  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) async => [parcels.parcel('one'), parcels.parcel('unused')];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> choose(WidgetTester tester, String value) async {
  final selector = find.byKey(const Key('finance-parcel-filter'));
  await tester.scrollUntilVisible(
    selector,
    -100,
    scrollable: find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    ),
  );
  // Read the visible menu label from the dropdown widget rather than duplicating localization.
  final dropdown = tester.widget<DropdownButton<String>>(
    find.descendant(
      of: selector,
      matching: find.byType(DropdownButton<String>),
    ),
  );
  final label =
      (dropdown.items!.singleWhere((item) => item.value == value).child as Text)
          .data!;
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  final one = find.byKey(const Key('finance-document-one'));
  final general = find.byKey(const Key('finance-document-general'));
  final two = find.byKey(const Key('finance-document-two'));
  testWidgets(
    'all general active and historic parcel selections keep complete totals',
    (tester) async {
      final actor = parcels.actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        parcels: _Parcels(),
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await choose(tester, 'general');
      expect(general, findsOneWidget);
      expect(one, findsNothing);
      await choose(tester, 'parcel:one');
      expect(one, findsOneWidget);
      expect(general, findsNothing);
      expect(two, findsNothing);
      expect(find.text('Chi: 4.000.000'), findsOneWidget);
      await choose(tester, 'parcel:historic');
      expect(two, findsOneWidget);
      expect(one, findsNothing);
      await choose(tester, 'all');
      expect(general, findsOneWidget);
      expect(one, findsOneWidget);
      expect(store.items.length, 5);
    },
  );
  testWidgets(
    'parcel combines with date kind and Unicode query and empty choice stays accessible',
    (tester) async {
      final actor = parcels.actor();
      final service = FinanceDocumentService(
        repository: _Store(),
        parcels: _Parcels(),
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(
          FinanceDocumentsScreen(
            service: service,
            pickPeriod: (_, initial) async => DateTimeRange(
              start: DateTime(2026, 10, 12),
              end: DateTime(2026, 10, 12),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-kind-payment')));
      await tester.tap(find.byKey(const Key('finance-period')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('finance-search')), 'ຂໍ້ມູນ');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await choose(tester, 'parcel:one');
      expect(one, findsOneWidget);
      expect(find.byKey(const Key('finance-document-old')), findsNothing);
      expect(find.byKey(const Key('finance-document-receipt')), findsNothing);
      expect(general, findsNothing);
      await choose(tester, 'parcel:unused');
      expect(find.text('Không tìm thấy chứng từ phù hợp.'), findsOneWidget);
      await choose(tester, 'all');
      expect(one, findsOneWidget);
      expect(find.byKey(const Key('finance-clear-period')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('finance-search')))
            .controller!
            .text,
        'ຂໍ້ມູນ',
      );
    },
  );
  testWidgets(
    'finance-only access can filter persisted links without reading parcel catalog',
    (tester) async {
      final actor = parcels.actor(viewParcel: false);
      final service = FinanceDocumentService(
        repository: _Store(),
        parcels: _Parcels(),
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('P-one · Lô one'), findsNothing);
      await choose(tester, 'parcel:historic');
      expect(two, findsOneWidget);
      expect(general, findsNothing);
    },
  );
  testWidgets('revocation hides documents after parcel selection rebuild', (
    tester,
  ) async {
    final initial = parcels.actor();
    AuthorizationSubject? live = initial;
    final service = FinanceDocumentService(
      repository: _Store(),
      subject: initial,
      currentSubject: () => live,
    );
    await tester.pumpWidget(
      fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    live = null;
    await tester.enterText(find.byKey(const Key('finance-search')), 'Mua');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finance-parcel-filter')), findsNothing);
    expect(one, findsNothing);
  });
  testWidgets(
    'parcel selector and documents scroll with keyboard on narrow enlarged screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      final actor = parcels.actor();
      final service = FinanceDocumentService(
        repository: _Store(),
        parcels: _Parcels(),
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        fixture.app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: FinanceDocumentsScreen(service: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await choose(tester, 'general');
      await tester.enterText(find.byKey(const Key('finance-search')), 'Mua');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        general,
        100,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(general, findsOneWidget);
      expect(one, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
