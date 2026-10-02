import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_application_service.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_use_cases.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_survey_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/controllers/land_parcel_controller.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_boundary_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements LandParcelRepository {
  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected write');
}

class _Surveys implements LandSurveyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected write');
}

class _App implements LandParcelApplication {
  _App(this.parcel);
  final LandParcel parcel;
  ReplaceBoundaryCommand? submitted;
  String? failure;
  @override
  Future<LandParcelApplicationResult<LandParcel>> replaceBoundary(
    AuthorizationSubject subject,
    ReplaceBoundaryCommand command,
  ) async {
    submitted = command;
    if (failure != null) {
      return LandParcelApplicationResult.failure(
        LandParcelApplicationStatus.validationFailed,
        failure!,
      );
    }
    return LandParcelApplicationResult.success(
      parcel,
      'landParcel.boundary.replaceSuccess',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected application call');
}

void main() {
  late LandParcel parcel;
  late _App app;
  late LandParcelController controller;
  setUp(() {
    parcel = LandParcel.create(
      id: 'plot',
      farmId: 'farm',
      parcelCode: 'AGR-NONG-T003',
      name: 'test',
      kind: ParcelLayer.fieldPlot,
      projectId: 'project',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16, longitude: 106),
        Wgs84Vertex(latitude: 16, longitude: 106.01),
        Wgs84Vertex(latitude: 16.01, longitude: 106.01),
        Wgs84Vertex(latitude: 16.01, longitude: 106),
      ]),
      boundarySource: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.draft,
      actorMembershipId: 'member',
      occurredAt: DateTime.utc(2026, 10, 2),
    );
    app = _App(parcel);
    controller = LandParcelController(
      subject: const AuthorizationSubject(
        userId: 'u',
        membershipId: 'member',
        farmId: 'farm',
        permissionCodes: {
          PermissionCodes.fieldView,
          PermissionCodes.fieldBoundaryEdit,
        },
        dataScopes: {DataScope.allFarm},
      ),
      parcels: _Repo(),
      surveys: _Surveys(),
      createLandParcel: CreateLandParcel(app),
      updateMetadata: UpdateLandParcelMetadata(app),
      completeGpsMeasurement: CompleteGpsMeasurement(app),
      verifyBoundary: VerifyBoundary(app),
      importPreview: ImportKmlKmzPreview(app),
      applyImportedBoundary: ApplyImportedBoundary(app),
      exportKmlKmz: ExportKmlKmz(app),
      replaceBoundary: ReplaceBoundary(app),
    );
  });
  tearDown(() => controller.dispose());
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LandParcelBoundaryEditScreen(
                    controller: controller,
                    parcel: parcel,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> moveCorner(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('boundary-edit-canvas')));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const Key('boundary-edit-canvas')));
    await tester.tapAt(
      rect.topLeft + Offset(rect.width * 0.2, rect.height * 0.8),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cancel edits writes nothing', (tester) async {
    await open(tester);
    await moveCorner(tester);
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(app.submitted, isNull);
  });
  testWidgets('zoom changes camera and pan does not submit a boundary', (
    tester,
  ) async {
    await open(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final before = viewer.transformationController!.value.clone();
    await tester.tap(find.byKey(const Key('boundary-zoom-in')));
    await tester.pumpAndSettle();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(before.getMaxScaleOnAxis()),
    );
    await tester.drag(
      find.byKey(const Key('boundary-edit-canvas')),
      const Offset(30, 20),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('boundary-edit-save')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('boundary-edit-save')))
          .onPressed,
      isNull,
    );
    expect(app.submitted, isNull);
  });
  testWidgets('save submits original snapshot and manual vertices', (
    tester,
  ) async {
    await open(tester);
    await moveCorner(tester);
    await tester.ensureVisible(find.byKey(const Key('boundary-edit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boundary-edit-save')));
    await tester.pumpAndSettle();
    expect(app.submitted!.expectedBoundaryVersion, parcel.boundaryVersion);
    expect(app.submitted!.expectedUpdatedAt, parcel.updatedAt);
    expect(app.submitted!.source, BoundarySource.manual);
    expect(
      app.submitted!.vertices.first,
      isNot(parcel.boundary.vertices.first),
    );
    expect(find.text('Open'), findsOneWidget);
  });
  testWidgets('rejected boundary stays open with localized reason', (
    tester,
  ) async {
    app.failure = 'boundaryEdit.outside';
    await open(tester);
    await moveCorner(tester);
    await tester.ensureVisible(find.byKey(const Key('boundary-edit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boundary-edit-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boundary-edit-error')), findsOneWidget);
    expect(
      find.text('Ranh giới Thửa vượt ra ngoài Lô hoặc phủ vùng loại trừ.'),
      findsOneWidget,
    );
    expect(find.byType(LandParcelBoundaryEditScreen), findsOneWidget);
  });
}
