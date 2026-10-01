import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/farm/application/land_parcel_parent_service.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/presentation/screens/land_parcel_parent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

LandParcel parcel(
  String id, {
  String? parent,
  ParcelLayer kind = ParcelLayer.fieldPlot,
}) => LandParcel.create(
  id: id,
  farmId: 'farm',
  parcelCode: id,
  name: id,
  kind: kind,
  parentBlockId: parent,
  projectId: 'project',
  boundary: Wgs84Polygon.fromVertices(const [
    Wgs84Vertex(latitude: 16, longitude: 106),
    Wgs84Vertex(latitude: 16, longitude: 106.01),
    Wgs84Vertex(latitude: 16.01, longitude: 106),
  ]),
  boundarySource: BoundarySource.manual,
  verificationStatus: BoundaryVerificationStatus.draft,
  actorMembershipId: 'member',
  occurredAt: DateTime.utc(2026, 10, 1),
);

class _UnusedRepository implements LandParcelRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository access');
}

class _ParentService extends LandParcelParentService {
  _ParentService(this.blocks) : super(_UnusedRepository());
  final List<LandParcel> blocks;
  int calls = 0;
  LandParcel? target;
  LandParcel? submitted;
  String? failure;
  @override
  Future<List<LandParcel>> listBlocks({
    required AuthorizationSubject subject,
    required LandParcel plot,
  }) async => blocks;
  @override
  Future<LandParcel> changeParent({
    required AuthorizationSubject subject,
    required LandParcel expectedPlot,
    required LandParcel? expectedParent,
  }) async {
    calls++;
    target = expectedParent;
    submitted = expectedPlot;
    if (failure != null) throw ParcelParentException(failure!);
    return expectedPlot.updateKind(
      kind: ParcelLayer.fieldPlot,
      parentBlockId: expectedParent?.id,
      actorMembershipId: subject.membershipId,
      occurredAt: DateTime.now().toUtc(),
    );
  }
}

void main() {
  const subject = AuthorizationSubject(
    userId: 'u',
    membershipId: 'member',
    farmId: 'farm',
    permissionCodes: {PermissionCodes.fieldView, PermissionCodes.fieldEdit},
    dataScopes: {DataScope.allFarm},
  );
  Future<void> open(
    WidgetTester tester,
    LandParcel plot,
    _ParentService service,
  ) async {
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
                MaterialPageRoute(
                  builder: (_) => LandParcelParentScreen(
                    subject: subject,
                    plot: plot,
                    service: service,
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

  testWidgets('cancel does not write and unchanged choice disables saving', (
    tester,
  ) async {
    final service = _ParentService([
      parcel('block', kind: ParcelLayer.landBlock),
    ]);
    await open(tester, parcel('AGR-NONG-T001'), service);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('parent-relation-save')))
          .onPressed,
      isNull,
    );
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(service.calls, 0);
  });

  testWidgets(
    'block selection submits stable plot identity and target snapshot',
    (tester) async {
      final target = parcel('block', kind: ParcelLayer.landBlock);
      final service = _ParentService([target]);
      final plot = parcel('AGR-NONG-T001');
      await open(tester, plot, service);
      await tester.tap(find.byKey(const Key('parent-option-block')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('parent-relation-save')));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(service.target, same(target));
      expect(service.submitted, same(plot));
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets('detach sends explicit null parent', (tester) async {
    final service = _ParentService([
      parcel('block', kind: ParcelLayer.landBlock),
    ]);
    await open(tester, parcel('AGR-NONG-T001', parent: 'block'), service);
    await tester.tap(find.byKey(const Key('parent-option-independent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('parent-relation-save')));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(service.target, isNull);
  });

  testWidgets(
    'failed placement keeps editor open and displays localized error',
    (tester) async {
      final service = _ParentService([
        parcel('block', kind: ParcelLayer.landBlock),
      ])..failure = 'outsideBlock';
      await open(tester, parcel('AGR-NONG-T001'), service);
      await tester.tap(find.byKey(const Key('parent-option-block')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('parent-relation-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent-relation-error')), findsOneWidget);
      expect(
        find.text(
          'Thửa không nằm hoàn toàn trong vùng đất hợp lệ của lô đích.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('parent-relation-save')), findsOneWidget);
    },
  );
}
