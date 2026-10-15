import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_summary.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/production_costs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/production_cost_summary_test.dart' as actors;
import 'finance_document_details_test.dart' as fixture;

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [fixture.document()];
  int reads = 0;
  void Function()? onRead;
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
  late _Store store;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late ProductionCostSummary service;
  setUp(() {
    store = _Store();
    initial = actors.actor();
    live = initial;
    service = ProductionCostSummary(
      FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => live,
      ),
    );
  });
  Future<void> openGroup(WidgetTester tester) async {
    await tester.pumpWidget(
      fixture.app(ProductionCostsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('costs-group-general-LAK')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('costs-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('costs-group-general-LAK')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('costs-document-one')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('costs-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cost document details read fresh values and preserve report after close',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openGroup(tester);
      store.items = [
        fixture.document(
          amount: 2000000,
          notes: List.filled(40, 'ຂໍ້ມູນ ').join(),
        ),
      ];
      await tester.tap(find.byKey(const Key('costs-document-one')));
      await tester.pumpAndSettle();
      expect(store.reads, 2);
      expect(find.text('Chi tiết chứng từ'), findsOneWidget);
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((w) => w.data),
        contains('Số tiền: 2.000.000 LAK'),
      );
      expect(find.byKey(const Key('finance-save')), findsNothing);
      await tester.tap(find.byKey(const Key('finance-details-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('costs-group-general-LAK')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('costs-parcel')),
        -100,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('costs-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('costs-parcel')),
            )
            .initialValue,
        'all',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('revoked reporting access prevents detail read', (tester) async {
    await openGroup(tester);
    live = actors.actor(report: false);
    await tester.tap(find.byKey(const Key('costs-document-one')));
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    expect(find.text('Chi tiết chứng từ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'report permission revoked during detail read prevents disclosure',
    (tester) async {
      await openGroup(tester);
      store.onRead = () {
        live = actors.actor(report: false);
      };
      await tester.tap(find.byKey(const Key('costs-document-one')));
      await tester.pumpAndSettle();
      expect(store.reads, 2);
      expect(find.text('Chi tiết chứng từ'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final foreign in [false, true]) {
    testWidgets('missing or foreign cost document is rejected: $foreign', (
      tester,
    ) async {
      await openGroup(tester);
      store.items = foreign ? [fixture.document(farm: 'other')] : [];
      await tester.tap(find.byKey(const Key('costs-document-one')));
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết chứng từ'), findsNothing);
      expect(find.text('Không thể tải chi tiết chứng từ.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
