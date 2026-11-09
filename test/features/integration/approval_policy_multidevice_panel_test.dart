import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/approval/approval_administration.dart';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/features/integration/presentation/approval_policy_panel.dart';

class Store implements ApprovalAdministration, RemoteApprovalAdministration {
  List<Map<String, Object?>> rows = [
    {
      'kind': 'machineRun',
      'currency': 'VND',
      'version': 1,
      'state': 'draft',
      'changed_by': 'author',
      'changed_at': '2026-11-01',
      'payload': 'PRIVATE-POLICY',
    },
  ];
  Completer<List<Map<String, Object?>>>? pending;
  int proposals = 0;
  @override
  Future<List<Map<String, Object?>>> list() async =>
      pending == null ? rows : await pending!.future;
  @override
  Future<void> syncPolicy(ApprovalKind kind, String currency) async {}
  @override
  Future<void> propose(DocumentApprovalPolicy p, String reason) async {
    proposals++;
  }

  @override
  Future<void> publishDraft(
    ApprovalKind kind,
    String currency,
    int version,
  ) async {}
  @override
  Future<void> activate(
    ApprovalKind kind,
    String currency,
    int version,
    int active,
    String reason,
  ) async {}
  @override
  Future<List<Map<String, Object?>>> policyHistory() async => [
    {'detail': 'PRIVATE-AUDIT'},
  ];
}

void main() {
  Widget app(Store store, String actor, bool read, {bool audit = true}) =>
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApprovalPolicyPanel(
              store: store,
              can: (permission) =>
                  permission == ApprovalRules.auditView ? audit && read : read,
              farm: 'f',
              actor: actor,
            ),
          ),
        ),
      );
  Future<void> open(WidgetTester t) async {
    await t.tap(find.text('Approval policy'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'audit-only revocation dismisses private dialog while policy read remains permitted',
    (t) async {
      final s = Store();
      await t.pumpWidget(app(s, 'one', true));
      await open(t);
      await t.tap(find.text('View audit'));
      await t.pumpAndSettle();
      expect(find.textContaining('PRIVATE-AUDIT'), findsOneWidget);
      await t.pumpWidget(app(s, 'one', true, audit: false));
      await t.pumpAndSettle();
      expect(find.textContaining('PRIVATE-AUDIT'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'late load response cannot display old account policy after account switch',
    (t) async {
      final s = Store()..pending = Completer();
      await t.pumpWidget(app(s, 'one', true));
      await open(t);
      await t.tap(find.text('Load policies'));
      await t.pump();
      await t.pumpWidget(app(s, 'two', true));
      s.pending!.complete(s.rows);
      await t.pumpAndSettle();
      expect(find.textContaining('PRIVATE-POLICY'), findsNothing);
    },
  );
  testWidgets(
    'revoked view clears cached rows even when the same user regains view',
    (t) async {
      final s = Store();
      await t.pumpWidget(app(s, 'one', true));
      await open(t);
      await t.tap(find.text('Load policies'));
      await t.pumpAndSettle();
      expect(find.textContaining('PRIVATE-POLICY'), findsOneWidget);
      await t.pumpWidget(app(s, 'one', false));
      await t.pump();
      await t.pumpWidget(app(s, 'one', true));
      await t.pumpAndSettle();
      expect(find.textContaining('PRIVATE-POLICY'), findsNothing);
    },
  );
  testWidgets(
    'account switch dismisses draft dialog and never submits old form',
    (t) async {
      final s = Store();
      await t.pumpWidget(app(s, 'one', true));
      await open(t);
      await t.tap(find.text('Propose draft'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.pumpWidget(app(s, 'two', true));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(s.proposals, 0);
      expect(t.takeException(), isNull);
    },
  );
}
