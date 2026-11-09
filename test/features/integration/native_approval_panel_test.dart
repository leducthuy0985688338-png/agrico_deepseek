import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/approval/native_approval_store.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/integration/presentation/native_approval_panel.dart';

class Store implements NativeApprovalStore {
  bool visible = true;
  int reads = 0;
  String? approvedReason;
  @override
  String get actorId => 'reviewer';
  @override
  bool canView([NativeApprovalView? item]) => visible;
  @override
  Future<List<NativeApprovalView>> list(Set<NativeApprovalType> types) async {
    reads++;
    return [
      NativeApprovalView(
        const NativeApprovalRef(
          NativeApprovalType.finance,
          'synthetic-private',
        ),
        ApprovalContext(
          farm: 'f',
          kind: ApprovalKind.cashPayment,
          sourceId: 'finance:synthetic-private',
          revision: 1,
          digest: 'synthetic-digest',
          creator: 'maker',
          createdAt: '2026-10-30T00:00:00Z',
          currency: 'LAK',
          total: '9007199254740991',
          policyVersion: 2,
        ),
        const ApprovalDecision(ApprovalOutcome.allowed, 'independentApproval'),
        {'state': 'pending'},
      ),
    ];
  }

  @override
  Future<ApprovalDecision> approve(NativeApprovalRef ref, String reason) async {
    approvedReason = reason;
    return const ApprovalDecision(
      ApprovalOutcome.allowed,
      'independentApproval',
    );
  }

  @override
  Future<void> submit(NativeApprovalRef ref) async {}
  @override
  Future<void> reject(NativeApprovalRef ref, String reason) async {}
  @override
  Future<List<Map<String, Object?>>> history(NativeApprovalRef ref) async => [];
  @override
  Future<void> proposeCommand({
    required String id,
    required String operation,
    required NativeApprovalRef target,
    required Map<String, Object?> payload,
  }) async {}
}

void main() {
  for (final lang in ['vi', 'en', 'lo'])
    testWidgets(
      'native panel localized source trace and access withdrawal $lang',
      (tester) async {
        final store = Store();
        Widget app() => MaterialApp(
          locale: Locale(lang),
          supportedLocales: const [Locale('vi'), Locale('en'), Locale('lo')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: NativeApprovalPanel(
              store: store,
              types: const {NativeApprovalType.finance},
            ),
          ),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(OutlinedButton).first);
        await tester.pumpAndSettle();
        expect(store.reads, 1);
        expect(find.textContaining('9007199254740991 LAK'), findsOneWidget);
        expect(find.textContaining('synthetic-digest'), findsOneWidget);
        store.visible = false;
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(find.textContaining('synthetic-private'), findsNothing);
        expect(find.textContaining('synthetic-digest'), findsNothing);
      },
    );
  testWidgets(
    'native approve requires explicit reason and dispatches to existing store',
    (tester) async {
      final store = Store();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: NativeApprovalPanel(
              store: store,
              types: const {NativeApprovalType.finance},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(OutlinedButton).first);
      await tester.pumpAndSettle();
      // Locate the enabled approval button by its behavior, independent of locale.
      final button = find.byType(FilledButton).first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('native-approval-reason')),
        'Synthetic independent review',
      );
      await tester.tap(find.byType(FilledButton).last);
      await tester.pumpAndSettle();
      expect(store.approvedReason, 'Synthetic independent review');
    },
  );
}
