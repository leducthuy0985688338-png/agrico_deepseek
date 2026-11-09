import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/update_household_contact.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/edit_household_contact_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saves edited contact and returns the same household code',
      (tester) async {
    final now = DateTime.utc(2026, 9, 1);
    final repository = _Households(Household(
      id: 'h1', farmId: 'farm-1', householdCode: 'H00001',
      headOfHouseholdName: 'Old name', phone: '123',
      administrativeLocation: const AdministrativeLocation(
        countryName: 'Lào', provinceName: 'Savannakhet',
        districtName: 'Nong', villageName: 'Ta Ko',
      ),
      active: true, createdAt: now, createdBy: 'member',
      updatedAt: now, updatedBy: 'member',
    ));
    const subject = AuthorizationSubject(
      userId: 'u', membershipId: 'editor', farmId: 'farm-1',
      permissionCodes: {PermissionCodes.householdEdit},
      dataScopes: {DataScope.allFarm},
    );
    Household? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('vi'),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async {
          result = await Navigator.of(context).push<Household>(
            MaterialPageRoute(builder: (_) => EditHouseholdContactScreen(
              household: repository.value, subject: subject,
              update: UpdateHouseholdContact(repository),
            )),
          );
        },
        child: const Text('Open'),
      ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('H00001'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('household-edit-head')),
        'ນາງ ສົມພອນ');
    await tester.enterText(find.byKey(const Key('household-edit-phone')), '');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('household-edit-save')));
    await tester.tap(find.byKey(const Key('household-edit-save')));
    await tester.pumpAndSettle();
    expect(repository.value.headOfHouseholdName, 'ນາງ ສົມພອນ');
    expect(repository.value.phone, isNull);
    expect(result?.householdCode, 'H00001');
  });
}

class _Households implements LandSurveyRepository {
  _Households(this.value);
  Household value;

  @override
  Future<Household?> getHousehold(String id) async =>
      value.id == id ? value : null;
  @override
  Future<void> updateHousehold(Household updated) async => value = updated;
  @override
  Future<T> transaction<T>(
      Future<T> Function(LandSurveyRepository repository) action) => action(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
