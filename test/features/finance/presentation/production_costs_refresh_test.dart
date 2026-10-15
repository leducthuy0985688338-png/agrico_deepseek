import 'dart:async';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/application/production_cost_summary.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/production_costs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../application/production_cost_summary_test.dart' as fixture;
import 'finance_document_details_test.dart' as app_fixture;
import 'production_cost_currency_filter_test.dart' as currency_ui;

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [fixture.document('one', 1000000)];
  int reads = 0;
  bool fail = false;
  Future<void>? gate;
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    if (gate != null) {
      await gate;
    }
    if (fail) {
      throw StateError('Read failed');
    }
    return List.of(items);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _Store store;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late ProductionCostSummary summary;
  final refresh = find.byKey(const Key('costs-refresh'));
  Future<void> pull(WidgetTester tester) async {
    await tester.drag(
      find.descendant(of: refresh, matching: find.byType(ListView)),
      const Offset(0, 350),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    store = _Store();
    initial = fixture.actor();
    live = initial;
    summary = ProductionCostSummary(
      FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => live,
      ),
    );
  });
  testWidgets('pull refresh reloads a short report', (tester) async {
    await tester.pumpWidget(
      app_fixture.app(ProductionCostsScreen(service: summary)),
    );
    await tester.pumpAndSettle();
    store.items = [fixture.document('new', 2000000)];
    await pull(tester);
    expect(store.reads, 2);
    expect(find.text('Tổng chi: 2.000.000 LAK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'refresh preserves parcel date currency and suppresses duplicate requests',
    (tester) async {
      final day = DateTime(2026, 10, 12);
      store.items = [
        fixture.document('one', 1000000, parcelId: 'one', date: day),
      ];
      await tester.pumpWidget(
        app_fixture.app(
          ProductionCostsScreen(
            service: summary,
            initialParcelId: 'one',
            pickPeriod: (_, _) async => DateTimeRange(start: day, end: day),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await currency_ui.chooseCurrency(tester, 'currency:LAK');
      await tester.tap(find.byKey(const Key('costs-period')));
      await tester.pumpAndSettle();
      final pending = Completer<void>();
      store.gate = pending.future;
      final before = store.reads;
      final callback = tester.widget<RefreshIndicator>(refresh).onRefresh;
      final loading = callback();
      await callback();
      expect(store.reads, before + 1);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('costs-refresh-button')))
            .onPressed,
        isNull,
      );
      store.items = [
        fixture.document('new', 2000000, parcelId: 'one', date: day),
        fixture.document('outside', 7000000),
      ];
      pending.complete();
      await loading;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('costs-parcel')),
            )
            .initialValue,
        'parcel:one',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('costs-currency')),
            )
            .initialValue,
        'currency:LAK',
      );
      expect(find.byKey(const Key('costs-clear-period')), findsOneWidget);
      expect(find.text('Tổng chi: 2.000.000 LAK'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('empty and failed reports allow pull to retry', (tester) async {
    store.items = [];
    await tester.pumpWidget(
      app_fixture.app(ProductionCostsScreen(service: summary)),
    );
    await tester.pumpAndSettle();
    store.fail = true;
    await pull(tester);
    expect(store.reads, 2);
    store.fail = false;
    store.items = [fixture.document('recovered', 3000000)];
    await pull(tester);
    expect(store.reads, 3);
    expect(find.text('Tổng chi: 3.000.000 LAK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('revoked permission blocks refresh without persisted read', (
    tester,
  ) async {
    await tester.pumpWidget(
      app_fixture.app(ProductionCostsScreen(service: summary)),
    );
    await tester.pumpAndSettle();
    live = fixture.actor(report: false);
    await tester.widget<RefreshIndicator>(refresh).onRefresh();
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    expect(find.byKey(const Key('costs-total-LAK')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending refresh can finish after disposal', (tester) async {
    await tester.pumpWidget(
      app_fixture.app(ProductionCostsScreen(service: summary)),
    );
    await tester.pumpAndSettle();
    final pending = Completer<void>();
    store.gate = pending.future;
    final loading = tester.widget<RefreshIndicator>(refresh).onRefresh();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await loading;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
