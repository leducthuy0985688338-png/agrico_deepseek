import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/localization/app_localizations.dart';
import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:agrico_deepseek/features/finance/presentation/finance_documents_screen.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:agrico_deepseek/features/farm/domain/repositories/land_parcel_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

AuthorizationSubject actor({bool viewParcel = true}) => AuthorizationSubject(
  userId: 'user',
  membershipId: 'member',
  farmId: 'farm-a',
  permissionCodes: {
    PermissionCodes.financeView,
    PermissionCodes.financeCreate,
    PermissionCodes.cashView,
    PermissionCodes.cashRecord,
    PermissionCodes.dataExport,
    PermissionCodes.reportFinance,
    if (viewParcel) PermissionCodes.fieldView,
  },
  dataScopes: const {DataScope.allFarm},
  validUntil: DateTime.now().add(const Duration(hours: 1)),
);

Future<FinanceDocument> create(
  FinanceDocumentService service, {
  String? parcelId,
}) => service.create(
  id: 'doc',
  organizationId: 'farm-a',
  kind: BusinessDocumentKind.payment,
  occurredAt: DateTime(2026),
  amountMinor: 1000000,
  currency: 'LAK',
  category: 'Test',
  parcelId: parcelId,
);

void main() {
  late _Store store;
  late _Parcels parcels;
  late AuthorizationSubject initial;
  late AuthorizationSubject live;
  late FinanceDocumentService service;
  setUp(() {
    store = _Store();
    parcels = _Parcels()..items = [parcel('one')];
    initial = actor();
    live = initial;
    service = FinanceDocumentService(
      repository: store,
      parcels: parcels,
      subject: initial,
      currentSubject: () => live,
    );
  });
  test(
    'general and linked documents preserve nullable parcel identity',
    () async {
      expect((await create(service)).parcelId, isNull);
      expect((await create(service, parcelId: 'one')).parcelId, 'one');
      expect((await service.availableParcels()).single.parcelCode, 'P-one');
      await service.exportReport(
        save: (workbook) async {
          expect(workbook['Finance V2'].rows.last[6]!.value.toString(), 'one');
        },
      );
    },
  );
  test('unknown, inactive and foreign parcels cannot be linked', () async {
    for (final value in [
      <LandParcel>[],
      [parcel('one', active: false)],
      [parcel('one', farm: 'other')],
      [parcel('different')],
    ]) {
      parcels.items = value;
      await expectLater(create(service, parcelId: 'one'), throwsStateError);
    }
    expect(store.documents, isEmpty);
  });
  test(
    'missing parcel view permits general documents but denies links',
    () async {
      live = actor(viewParcel: false);
      expect(await service.availableParcels(), isEmpty);
      expect((await create(service)).parcelId, isNull);
      await expectLater(create(service, parcelId: 'one'), throwsStateError);
      expect(store.documents, hasLength(1));
    },
  );
  test(
    'revoked parcel grant during validation prevents finance write',
    () async {
      parcels.onRead = () {
        live = actor(viewParcel: false);
      };
      await expectLater(create(service, parcelId: 'one'), throwsStateError);
      expect(store.documents, isEmpty);
    },
  );
  test('foreign parcel list fails closed', () async {
    parcels.items = [parcel('one', farm: 'other')];
    await expectLater(service.availableParcels(), throwsStateError);
  });
  testWidgets(
    'selecting a parcel saves its ID and displays its business label',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: FinanceDocumentsScreen(service: service),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finance-parcel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P-one · Lô one').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('finance-category')), 'Test');
      await tester.enterText(
        find.byKey(const Key('finance-amount')),
        '1000000',
      );
      await tester.tap(find.byKey(const Key('finance-save')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(store.documents.single.parcelId, 'one');
      expect(find.textContaining('P-one · Lô one'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Parcels implements LandParcelRepository {
  List<LandParcel> items = [];
  void Function()? onRead;
  @override
  Future<List<LandParcel>> listByFarm(
    String farmId, {
    bool includeInactive = false,
  }) async {
    onRead?.call();
    return List.of(items);
  }

  @override
  Future<LandParcel?> getById({
    required String farmId,
    required String id,
  }) async {
    onRead?.call();
    return items.isEmpty ? null : items.first;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

LandParcel parcel(String id, {String farm = 'farm-a', bool active = true}) =>
    LandParcel.create(
      id: id,
      farmId: farm,
      parcelCode: 'P-$id',
      name: 'Lô $id',
      boundary: Wgs84Polygon.fromVertices(const [
        Wgs84Vertex(latitude: 16, longitude: 106),
        Wgs84Vertex(latitude: 16, longitude: 106.001),
        Wgs84Vertex(latitude: 16.001, longitude: 106.001),
        Wgs84Vertex(latitude: 16.001, longitude: 106),
      ]),
      boundarySource: BoundarySource.manual,
      verificationStatus: BoundaryVerificationStatus.draft,
      actorMembershipId: 'member',
      occurredAt: DateTime(2026),
      active: active,
    );

class _Store implements FinanceDocumentStore {
  final documents = <FinanceDocument>[];

  @override
  Future<FinanceDocument> create({
    required String id,
    required String organizationId,
    required BusinessDocumentKind kind,
    required DateTime occurredAt,
    required int amountMinor,
    required String currency,
    required String category,
    String? parcelId,
    String? description,
  }) async {
    final document = FinanceDocument(
      id: id,
      organizationId: organizationId,
      code: BusinessReferenceCode.forDate(
        kind: kind,
        date: occurredAt,
        sequence: documents.length + 1,
      ).toString(),
      kind: kind,
      occurredAt: occurredAt,
      amountMinor: amountMinor,
      currency: currency,
      category: category,
      parcelId: parcelId,
      description: description,
    );
    documents.add(document);
    return document;
  }

  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async =>
      documents.where((doc) => doc.organizationId == organizationId).toList();
}
