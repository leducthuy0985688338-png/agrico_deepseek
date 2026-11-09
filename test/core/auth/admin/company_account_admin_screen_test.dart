import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agrico_deepseek/core/auth/admin/company_account_admin_screen.dart';
import 'package:agrico_deepseek/core/auth/admin/company_account_admin_service.dart';
import 'package:agrico_deepseek/core/auth/company_membership.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/company_roles.dart';
import 'company_account_admin_service_test.dart' show Repository;

void main() {
  late Repository repository;
  late CompanyAccountAdminService service;
  late CompanyAccountRecord own;
  setUp(() {
    repository = Repository();
    own = CompanyAccountRecord(
      displayName: 'Admin',
      membership: CompanyMembership(
        profile: CompanyAccessProfile(
          userId: 'admin',
          membershipId: 'admin',
          farmId: 'local-farm',
          roles: [RoleAssignment(CompanyRole.systemAdmin)],
        ),
        offlineUntil: DateTime.now().toUtc().add(const Duration(days: 7)),
      ),
    );
    service = CompanyAccountAdminService(
      repository: repository,
      subject: own.membership.profile.subject(now: DateTime.now()),
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
    home: CompanyAccountAdminScreen(service: service),
  );
  testWidgets(
    'creation describes existing Auth account requirement and rejects empty form',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-add')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Firebase Authentication trước'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('account-save')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(Form),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();
      expect(repository.writes, 0);
      expect(find.text('Xác nhận hồ sơ quyền'), findsNothing);
    },
  );
  testWidgets('server denial shows message and does not show stale list', (
    tester,
  ) async {
    service = CompanyAccountAdminService(
      repository: _Denied(),
      subject: service.subject,
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Không đủ quyền máy chủ'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-admin')), findsNothing);
  });
  testWidgets('own profile has no save action', (tester) async {
    service = CompanyAccountAdminService(
      repository: _Own(own),
      subject: service.subject,
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-admin')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hồ sơ của bạn chỉ được xem'), findsOneWidget);
    expect(find.byKey(const Key('account-save')), findsNothing);
  });
}

class _Denied extends Repository {
  @override
  Future<List<CompanyAccountRecord>> list(String farmId) async =>
      throw const AccountAdminFailure('denied');
}

class _Own extends Repository {
  _Own(this.record);
  final CompanyAccountRecord record;
  @override
  Future<List<CompanyAccountRecord>> list(String farmId) async => [record];
}
