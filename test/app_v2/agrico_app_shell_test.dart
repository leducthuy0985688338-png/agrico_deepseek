import 'package:agrico_deepseek/app_v2/agrico_app_shell.dart';
import 'package:agrico_deepseek/core/localization/app_locale_controller.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_use_cases.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/controllers/land_parcel_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  AuthorizationSubject subject({bool allowed = true}) => AuthorizationSubject(
    userId: 'user',
    membershipId: 'member',
    farmId: 'farm',
    permissionCodes: allowed ? PermissionCodes.values : const {},
    dataScopes: const {DataScope.allFarm},
  );
  LandParcelController controller(AuthorizationSubject subject) {
    final parcels = _EmptyParcels();
    final app = LandParcelApplicationService(repository: parcels);
    return LandParcelController(
      subject: subject,
      parcels: parcels,
      surveys: _EmptySurveys(),
      createLandParcel: CreateLandParcel(app),
      updateMetadata: UpdateLandParcelMetadata(app),
      completeGpsMeasurement: CompleteGpsMeasurement(app),
      importPreview: ImportKmlKmzPreview(app),
      applyImportedBoundary: ApplyImportedBoundary(app),
      exportKmlKmz: ExportKmlKmz(app),
    );
  }

  Widget testApp({
    String locale = 'en',
    bool allowed = true,
    VoidCallback? parcels,
    VoidCallback? create,
  }) {
    final actor = subject(allowed: allowed);
    return ChangeNotifierProvider(
      create: (_) => AppLocaleController(initialLocale: Locale(locale)),
      child: Consumer<AppLocaleController>(
        builder: (context, language, _) => MaterialApp(
          locale: language.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AgricoAppShell(
            subject: actor,
            landParcelController: controller(actor),
            openLandParcels: parcels ?? () {},
            openCreateParcel: create ?? () {},
            legacyRoutes: const {},
          ),
        ),
      ),
    );
  }

  testWidgets('shell renders Home and five navigation destinations', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    expect(find.byKey(const Key('home-v2')), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Modules, Reports and Profile destinations open', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('Modules'));
    await tester.pump();
    expect(find.byKey(const Key('modules-v2')), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pump();
    expect(find.text('Reports'), findsWidgets);
    await tester.tap(find.text('Profile'));
    await tester.pump();
    expect(find.byKey(const Key('profile-v2')), findsOneWidget);
  });

  testWidgets('central Create opens permission-aware quick create', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Land parcels'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
  });

  testWidgets('parcel module and quick create invoke v2 production routes', (
    tester,
  ) async {
    var listOpened = 0;
    var formOpened = 0;
    await tester.pumpWidget(
      testApp(parcels: () => listOpened++, create: () => formOpened++),
    );
    await tester.tap(find.text('Modules'));
    await tester.pump();
    await tester.tap(find.text('Land parcels'));
    expect(listOpened, 1);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Land parcels'),
      ),
    );
    expect(formOpened, 1);
  });

  testWidgets('unauthorized parcel navigation is disabled', (tester) async {
    var opened = 0;
    await tester.pumpWidget(testApp(allowed: false, parcels: () => opened++));
    await tester.tap(find.text('Modules'));
    await tester.pump();
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Land parcels'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.enabled, isFalse);
    await tester.tap(find.text('Land parcels'), warnIfMissed: false);
    expect(opened, 0);
  });

  testWidgets('VI LO EN labels and runtime language switch work', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(locale: 'vi'));
    expect(find.text('Trang chủ'), findsOneWidget);
    await tester.tap(find.text('Cá nhân'));
    await tester.pump();
    await tester.tap(find.text('ລາວ'));
    await tester.pumpAndSettle();
    expect(find.text('ໜ້າຫຼັກ'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'Home uses unavailable KPI values instead of fake numbers on small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(testApp());
      expect(find.text('—'), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    },
  );
}

class _EmptyParcels implements LandParcelRepository {
  @override
  Future<void> create(LandParcel parcel) async {}
  @override
  Future<LandParcel?> getById({
    required String farmId,
    required String id,
  }) async => null;
  @override
  Future<LandParcel?> getByParcelCode({
    required String farmId,
    required String parcelCode,
  }) async => null;
  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) async => [];
  @override
  Future<void> saveBoundaryVersion(LandParcelBoundaryVersion version) async {}
  @override
  Future<void> setActive({
    required String farmId,
    required String id,
    required bool active,
    required String actorMembershipId,
    required DateTime occurredAt,
  }) async {}
  @override
  Future<T> transaction<T>(
    Future<T> Function(LandParcelRepository repository) action,
  ) => action(this);
  @override
  Future<void> update(LandParcel parcel) async {}
}

class _EmptySurveys implements LandSurveyRepository {
  @override
  Future<void> createAttachment(ParcelAttachment value) async {}
  @override
  Future<void> createCrop(CropRecord value) async {}
  @override
  Future<void> createHousehold(Household value) async {}
  @override
  Future<void> createSurvey(LandParcelSurvey value) async {}
  @override
  Future<Household?> getHousehold(String id) async => null;
  @override
  Future<LandUseProfile?> getLandUseProfile(String parcelId) async => null;
  @override
  Future<List<ParcelAttachment>> listAttachments(String parcelId) async => [];
  @override
  Future<List<CropRecord>> listCrops(
    String parcelId, {
    bool includeInactive = false,
  }) async => [];
  @override
  Future<List<Household>> listHouseholds(String farmId) async => [];
  @override
  Future<List<LandParcelSurvey>> listSurveys(String parcelId) async => [];
  @override
  Future<void> saveLandUseProfile(LandUseProfile value) async {}
  @override
  Future<T> transaction<T>(
    Future<T> Function(LandSurveyRepository repository) action,
  ) => action(this);
  @override
  Future<void> updateCrop(CropRecord value) async {}
  @override
  Future<void> updateHousehold(Household value) async {}
}
