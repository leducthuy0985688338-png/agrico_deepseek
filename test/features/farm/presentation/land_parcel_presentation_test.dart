import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_use_cases.dart';
import 'package:agrico_deepseek/features/farm/data/interchange/kml_interchange.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_survey.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/controllers/land_parcel_controller.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/boundary_history_screen.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_detail_screen.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_form_screen.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_list_screen.dart';
import 'package:agrico_deepseek/features/farm/presentation/widgets/boundary_workflow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final time = DateTime.utc(2026, 9, 8);
  LandParcel parcel({bool verified = false}) {
    var value = LandParcel.create(
      id: 'parcel-1',
      farmId: 'farm-1',
      parcelCode: 'P-001',
      name: 'Lô cà phê ກາເຟ',
      ownerHouseholdId: 'hh-1',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16.5, longitude: 104.7),
        Wgs84Vertex(latitude: 16.5, longitude: 104.701),
        Wgs84Vertex(latitude: 16.501, longitude: 104.7),
      ]),
      boundarySource: BoundarySource.gps,
      verificationStatus: verified
          ? BoundaryVerificationStatus.verified
          : BoundaryVerificationStatus.measured,
      actorMembershipId: 'member-1',
      occurredAt: time,
    );
    if (!verified) {
      value = value.replaceBoundary(
        boundary: Wgs84Polygon.fromVertices(const [
          Wgs84Vertex(latitude: 16.5, longitude: 104.7),
          Wgs84Vertex(latitude: 16.5, longitude: 104.702),
          Wgs84Vertex(latitude: 16.502, longitude: 104.7),
        ]),
        source: BoundarySource.googleEarth,
        verificationStatus: BoundaryVerificationStatus.measured,
        actorMembershipId: 'member-1',
        occurredAt: time.add(const Duration(days: 1)),
      );
    }
    return value;
  }

  Household household() => Household(
    id: 'hh-1',
    farmId: 'farm-1',
    householdCode: 'H-01',
    headOfHouseholdName: 'ນາງ ສົມພອນ',
    phone: '020123',
    administrativeLocation: const AdministrativeLocation(
      countryName: 'ລາວ',
      provinceName: 'ຈຳປາສັກ',
      districtName: 'ປາກເຊ',
      villageName: 'ບ້ານ ໃໝ່',
    ),
    active: true,
    createdAt: time,
    createdBy: 'member-1',
    updatedAt: time,
    updatedBy: 'member-1',
  );

  CropRecord crop(String id, String type) => CropRecord(
    id: id,
    parcelId: 'parcel-1',
    cropType: type,
    quantity: 10,
    unit: 'tree',
    condition: CropCondition.healthy,
    active: true,
    createdAt: time,
    createdBy: 'member-1',
    updatedAt: time,
    updatedBy: 'member-1',
  );

  LandParcelController controller({
    Set<String>? permissions,
    List<LandParcel>? source,
  }) {
    final parcelRepository = _MemoryParcelRepository(source ?? [parcel()]);
    final surveyRepository = _MemorySurveyRepository(
      households: [household()],
      crops: [crop('crop-1', 'Coffee'), crop('crop-2', 'Banana')],
      attachments: [
        ParcelAttachment(
          id: 'a-1',
          parcelId: 'parcel-1',
          attachmentType: ParcelAttachmentType.photo,
          fileName: 'ຮູບ.jpg',
          mimeType: 'image/jpeg',
          createdAt: time,
          createdBy: 'member-1',
        ),
      ],
    );
    final application = LandParcelApplicationService(
      repository: parcelRepository,
    );
    return LandParcelController(
      subject: AuthorizationSubject(
        userId: 'user-1',
        membershipId: 'member-1',
        farmId: 'farm-1',
        permissionCodes: permissions ?? PermissionCodes.values,
        dataScopes: const {DataScope.allFarm},
      ),
      parcels: parcelRepository,
      surveys: surveyRepository,
      createLandParcel: CreateLandParcel(application),
      updateMetadata: UpdateLandParcelMetadata(application),
      completeGpsMeasurement: CompleteGpsMeasurement(application),
      importPreview: ImportKmlKmzPreview(application),
      applyImportedBoundary: ApplyImportedBoundary(application),
      exportKmlKmz: ExportKmlKmz(application),
    );
  }

  Widget app(Widget child, {String locale = 'en'}) => MaterialApp(
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );

  testWidgets('list renders loading, canonical data, search and empty state', (
    tester,
  ) async {
    final value = controller();
    await tester.pumpWidget(app(LandParcelListScreen(controller: value)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('P-001'), findsOneWidget);
    expect(find.textContaining('ບ້ານ ໃໝ່'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('parcel-search')), 'missing');
    await tester.pump();
    expect(find.text('No land parcels yet.'), findsOneWidget);
  });

  testWidgets('create action is hidden without permission', (tester) async {
    final value = controller(permissions: const {PermissionCodes.fieldView});
    await tester.pumpWidget(app(LandParcelListScreen(controller: value)));
    await tester.pumpAndSettle();
    expect(find.text('Create parcel'), findsNothing);
  });

  for (final language in {
    'vi': 'Danh sách lô đất',
    'lo': 'ລາຍການແປງດິນ',
    'en': 'Land parcels',
  }.entries) {
    testWidgets(
      '${language.key.toUpperCase()} presentation renders localized text',
      (tester) async {
        await tester.pumpWidget(
          app(
            LandParcelListScreen(controller: controller(source: [])),
            locale: language.key,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(language.value), findsOneWidget);
      },
    );
  }

  testWidgets('detail renders household, Lao location, crops and attachment', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        LandParcelDetailScreen(controller: controller(), parcelId: 'parcel-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ນາງ ສົມພອນ'), findsWidgets);
    expect(find.textContaining('ບ້ານ ໃໝ່'), findsWidgets);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Banana'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ຮູບ.jpg'), 300);
    expect(find.text('ຮູບ.jpg'), findsOneWidget);
  });

  testWidgets(
    'form validates identity, derived geometry is read-only and crops are dynamic',
    (tester) async {
      var submitted = false;
      await tester.pumpWidget(
        app(
          LandParcelFormScreen(
            parcel: parcel(),
            household: household(),
            crops: [crop('c-1', 'Coffee')],
            onSubmit: (_) async {
              submitted = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('area-readonly')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.byKey(const Key('area-readonly')), findsOneWidget);
      expect(find.byKey(const Key('perimeter-readonly')), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Coffee'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Coffee'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();
      expect(find.text('Coffee'), findsNothing);
      await tester.dragUntilVisible(
        find.byKey(const Key('save-parcel')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.byKey(const Key('save-parcel')));
      await tester.pumpAndSettle();
      expect(submitted, isTrue);
    },
  );

  testWidgets('boundary history is read-only and renders multiple versions', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(BoundaryHistoryScreen(history: parcel().boundaryHistory)),
    );
    expect(find.byKey(const Key('boundary-version-1')), findsOneWidget);
    expect(find.byKey(const Key('boundary-version-2')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('invalid GPS polygon disables apply', (tester) async {
    final value = parcel();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: GpsBoundaryPreview(
            controller: controller(),
            parcel: value,
            completedVertices: const [Wgs84Vertex(latitude: 1, longitude: 1)],
          ),
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('apply-gps-boundary')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('The land parcel boundary is invalid.'), findsOneWidget);
  });

  testWidgets('KML warning renders and preview itself does not mutate parcel', (
    tester,
  ) async {
    final value = parcel();
    const codec = KmlInterchangeCodec();
    final preview = codec
        .importKml(
          '<kml><Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>104.7,16.5 104.701,16.5 104.7,16.501</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark></kml>',
        )
        .previews
        .single;
    final before = value.boundaryVersion;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: KmlImportPreviewView(
            controller: controller(),
            parcel: value,
            preview: preview,
          ),
        ),
      ),
    );
    expect(find.text('This file has no AGRICO metadata.'), findsOneWidget);
    expect(value.boundaryVersion, before);
  });

  test('open in Google Earth unavailable path is safe and localized', () async {
    final value = controller();
    expect(await value.openInGoogleEarth('parcel-1'), isFalse);
    expect(value.phase, ParcelPresentationPhase.persistenceError);
    expect(value.messageKey, 'googleEarth.openUnavailable');
  });
}

class _MemoryParcelRepository implements LandParcelRepository {
  _MemoryParcelRepository(List<LandParcel> values)
    : values = {for (final value in values) value.id: value};
  final Map<String, LandParcel> values;
  @override
  Future<void> create(LandParcel value) async {
    values[value.id] = value;
  }

  @override
  Future<LandParcel?> getById({
    required String farmId,
    required String id,
  }) async => values[id];
  @override
  Future<LandParcel?> getByParcelCode({
    required String farmId,
    required String parcelCode,
  }) async => values.values
      .where((value) => value.parcelCode == parcelCode)
      .firstOrNull;
  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) async => values.values.toList();
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
  Future<void> update(LandParcel value) async {
    values[value.id] = value;
  }
}

class _MemorySurveyRepository implements LandSurveyRepository {
  _MemorySurveyRepository({
    this.households = const [],
    this.crops = const [],
    this.attachments = const [],
  });
  final List<Household> households;
  final List<CropRecord> crops;
  final List<ParcelAttachment> attachments;
  @override
  Future<void> createAttachment(ParcelAttachment value) async {}
  @override
  Future<void> createCrop(CropRecord value) async {}
  @override
  Future<void> createHousehold(Household value) async {}
  @override
  Future<void> createSurvey(LandParcelSurvey value) async {}
  @override
  Future<Household?> getHousehold(String id) async =>
      households.where((value) => value.id == id).firstOrNull;
  @override
  Future<LandUseProfile?> getLandUseProfile(String parcelId) async => null;
  @override
  Future<List<ParcelAttachment>> listAttachments(String parcelId) async =>
      attachments.where((value) => value.parcelId == parcelId).toList();
  @override
  Future<List<CropRecord>> listCrops(
    String parcelId, {
    bool includeInactive = false,
  }) async => crops.where((value) => value.parcelId == parcelId).toList();
  @override
  Future<List<Household>> listHouseholds(String farmId) async =>
      households.where((value) => value.farmId == farmId).toList();
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
