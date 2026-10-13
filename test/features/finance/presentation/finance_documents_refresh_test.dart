import 'dart:async';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'finance_document_details_test.dart' as app_fixture;
import 'finance_filtered_totals_test.dart' as fixture;
import 'finance_document_parcel_filter_test.dart' as parcel_ui;

class _Store implements FinanceDocumentStore {
  List<FinanceDocument> items = [fixture.document('old')];
  bool fail = false;
  int reads = 0;
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
  final refresh = find.byKey(const Key('finance-refresh'));
  testWidgets(
    'pull refresh updates persisted rows and total for a short list',
    (tester) async {
      final actor = fixture.actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: actor,
        currentSubject: () => actor,
      );
      await tester.pumpWidget(
        app_fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      store.items = [fixture.document('new', amount: 2000000)];
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(store.reads, 2);
      expect(find.byKey(const Key('finance-document-new')), findsOneWidget);
      expect(find.byKey(const Key('finance-document-old')), findsNothing);
      expect(find.text('Chi: 2.000.000'), findsOneWidget);
    },
  );
  testWidgets(
    'refresh retains all four filters and does not duplicate concurrent reads',
    (tester) async {
      final actor = fixture.actor();
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: actor,
        currentSubject: () => actor,
      );
      final date = DateTime(2026, 10, 12);
      await tester.pumpWidget(
        app_fixture.app(
          FinanceDocumentsScreen(
            service: service,
            pickPeriod: (_, initial) async =>
                DateTimeRange(start: date, end: date),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-kind-payment')));
      await tester.tap(find.byKey(const Key('finance-period')));
      await tester.pumpAndSettle();
      await parcel_ui.choose(tester, 'parcel:one');
      await tester.enterText(find.byKey(const Key('finance-search')), 'ຂໍ້ມູນ');
      store.items = [
        fixture.document('new'),
        fixture.document('general', parcel: null),
        fixture.document('receipt', receipt: true),
        fixture.document('outside', day: 9),
      ];
      final pending = Completer<void>();
      store.gate = pending.future;
      final callback = tester.widget<RefreshIndicator>(refresh).onRefresh;
      final loading = callback();
      await callback();
      expect(store.reads, 2);
      pending.complete();
      await loading;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finance-document-new')), findsOneWidget);
      for (final id in ['general', 'receipt', 'outside']) {
        expect(find.byKey(Key('finance-document-$id')), findsNothing);
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('finance-search')))
            .controller!
            .text,
        'ຂໍ້ມູນ',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('finance-kind-payment')))
            .selected,
        isTrue,
      );
      expect(find.text('2026-10-12 – 2026-10-12'), findsOneWidget);
    },
  );
  testWidgets('empty and failed lists remain pullable and recover on retry', (
    tester,
  ) async {
    final actor = fixture.actor();
    final store = _Store()..items = [];
    final service = FinanceDocumentService(
      repository: store,
      subject: actor,
      currentSubject: () => actor,
    );
    await tester.pumpWidget(
      app_fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(store.reads, 2);
    expect(
      tester.widget<ListView>(find.byType(ListView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );
    store.fail = false;
    store.items = [fixture.document('recovered')];
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(store.reads, 3);
    expect(find.byKey(const Key('finance-document-recovered')), findsOneWidget);
  });
  testWidgets(
    'revoked access blocks refresh reads and hides cached documents',
    (tester) async {
      final initial = fixture.actor();
      AuthorizationSubject? live = initial;
      final store = _Store();
      final service = FinanceDocumentService(
        repository: store,
        subject: initial,
        currentSubject: () => live,
      );
      await tester.pumpWidget(
        app_fixture.app(FinanceDocumentsScreen(service: service)),
      );
      await tester.pumpAndSettle();
      live = null;
      await tester.widget<RefreshIndicator>(refresh).onRefresh();
      await tester.pumpAndSettle();
      expect(store.reads, 1);
      expect(find.byKey(const Key('finance-document-old')), findsNothing);
    },
  );
  testWidgets('pending refresh completes safely after screen disposal', (
    tester,
  ) async {
    final actor = fixture.actor();
    final store = _Store();
    final service = FinanceDocumentService(
      repository: store,
      subject: actor,
      currentSubject: () => actor,
    );
    await tester.pumpWidget(
      app_fixture.app(FinanceDocumentsScreen(service: service)),
    );
    await tester.pumpAndSettle();
    final pending = Completer<void>();
    store.gate = pending.future;
    final loading = tester.widget<RefreshIndicator>(refresh).onRefresh();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await loading;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
