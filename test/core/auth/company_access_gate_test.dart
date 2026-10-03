import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/auth/company_access_gate.dart';
import 'package:agrico_deepseek/core/auth/company_session.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'company_auth_test_support.dart';

void main() {
  late Gateway gateway;
  late MemoryStore store;
  late CompanySessionService service;
  late DateTime now;
  setUp(() {
    gateway = Gateway();
    store = MemoryStore();
    now = start;
    service = CompanySessionService(
      gateway: gateway,
      store: store,
      clock: () => now,
    );
  });
  Widget app() => MaterialApp(
    locale: const Locale('vi'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: CompanyAccessGate(
      service: service,
      sessionBuilder: (subject, logout) => Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Text('signed-in:${subject.userId}'),
              FilledButton(onPressed: logout, child: const Text('logout')),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('private-route')),
                  ),
                ),
                child: const Text('open-private'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  testWidgets('wrong password never opens business routes', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('company-email')),
      'person@company.example',
    );
    await tester.enterText(find.byKey(const Key('company-password')), 'wrong');
    await tester.ensureVisible(find.byKey(const Key('company-sign-in')));
    await tester.tap(find.byKey(const Key('company-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('signed-in:user'), findsNothing);
    expect(find.byKey(const Key('company-message')), findsOneWidget);
    expect(store.value, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('login and logout dispose the authenticated session', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('company-email')),
      'person@company.example',
    );
    await tester.enterText(
      find.byKey(const Key('company-password')),
      'correct',
    );
    await tester.ensureVisible(find.byKey(const Key('company-sign-in')));
    await tester.tap(find.byKey(const Key('company-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('signed-in:user'), findsOneWidget);
    await tester.tap(find.text('logout'));
    await tester.pumpAndSettle();
    expect(find.text('signed-in:user'), findsNothing);
    expect(store.value, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('verified session reopens offline without requesting password', (
    tester,
  ) async {
    await service.login('person@company.example', 'correct');
    gateway.fetchError = const AccessUnavailable();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('signed-in:user'), findsOneWidget);
    expect(service.offline, isTrue);
    expect(find.byKey(const Key('company-password')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('expiry removes a pushed private route, not only home', (
    tester,
  ) async {
    await service.login('person@company.example', 'correct');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-private'));
    await tester.pumpAndSettle();
    expect(find.text('private-route'), findsOneWidget);
    now = start.add(const Duration(days: 2));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('private-route'), findsNothing);
    expect(find.byKey(const Key('company-email')), findsOneWidget);
    expect(store.value, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('revocation on resume closes the whole route stack', (
    tester,
  ) async {
    await service.login('person@company.example', 'correct');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-private'));
    await tester.pumpAndSettle();
    gateway.fetchError = const AccessFailure('membershipDenied');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('private-route'), findsNothing);
    expect(store.value, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
