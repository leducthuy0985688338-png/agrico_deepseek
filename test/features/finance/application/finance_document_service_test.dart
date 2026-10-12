import 'package:agrico_deepseek/core/identity/domain/business_reference_code.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/features/finance/application/finance_document_service.dart';
import 'package:agrico_deepseek/features/finance/domain/finance_document.dart';
import 'package:flutter_test/flutter_test.dart';

AuthorizationSubject actor({
  Set<String> permissions = const {
    PermissionCodes.financeView,
    PermissionCodes.financeCreate,
    PermissionCodes.reportFinance,
  },
  Set<DataScope> scopes = const {DataScope.allFarm},
  Map<String, Set<DataScope>> overrides = const {},
  String user = 'user',
  String member = 'member',
  String farm = 'farm-a',
  bool active = true,
  bool expired = false,
  bool deadline = true,
}) => AuthorizationSubject(
  userId: user,
  membershipId: member,
  farmId: farm,
  permissionCodes: permissions,
  dataScopes: scopes,
  permissionScopes: overrides,
  active: active,
  validUntil: deadline
      ? DateTime.now().add(Duration(hours: expired ? -1 : 1))
      : null,
);

Future<FinanceDocument> create(
  FinanceDocumentService service, {
  String farm = 'farm-a',
}) => service.create(
  id: 'id',
  organizationId: farm,
  kind: BusinessDocumentKind.payment,
  occurredAt: DateTime(2026),
  amountMinor: 100,
  currency: 'LAK',
  category: 'category',
);

void main() {
  late _Store store;
  late AuthorizationSubject initial;
  late AuthorizationSubject? live;
  late FinanceDocumentService service;
  setUp(() {
    store = _Store();
    initial = actor();
    live = initial;
    service = FinanceDocumentService(
      repository: store,
      subject: initial,
      currentSubject: () => live,
    );
  });

  test('authorized create, view and report use the captured farm', () async {
    await create(service);
    expect((await service.listByOrganization('farm-a')).single.currency, 'LAK');
    var writes = 0;
    await service.exportReport(
      save: (workbook) async {
        writes++;
        expect(workbook['Finance V2'].rows, hasLength(2));
      },
    );
    expect(writes, 1);
    expect(store.creates, 1);
  });

  test('view grant does not grant create or report', () async {
    live = actor(permissions: {PermissionCodes.financeView});
    expect(await service.listByOrganization('farm-a'), isEmpty);
    await expectLater(create(service), throwsStateError);
    await expectLater(
      service.exportReport(save: (_) async {}),
      throwsStateError,
    );
    expect(store.creates, 0);
  });

  test('create and report grants require the view grant', () async {
    live = actor(
      permissions: {
        PermissionCodes.financeCreate,
        PermissionCodes.reportFinance,
      },
    );
    await expectLater(create(service), throwsStateError);
    await expectLater(
      service.exportReport(save: (_) async {}),
      throwsStateError,
    );
    expect(store.reads, 0);
    expect(store.creates, 0);
  });

  test('foreign organization is rejected before storage', () async {
    await expectLater(create(service, farm: 'farm-b'), throwsStateError);
    await expectLater(service.listByOrganization('farm-b'), throwsStateError);
    expect(store.reads, 0);
    expect(store.creates, 0);
  });

  test(
    'narrow scopes and explicit permission overrides deny whole-farm reads',
    () async {
      live = actor(scopes: {DataScope.own});
      await expectLater(service.listByOrganization('farm-a'), throwsStateError);
      live = actor(overrides: {PermissionCodes.financeView: {}});
      await expectLater(service.listByOrganization('farm-a'), throwsStateError);
      expect(store.reads, 0);
    },
  );

  test(
    'inactive, expired, missing deadline and changed identity fail closed',
    () async {
      for (final subject in <AuthorizationSubject?>[
        null,
        actor(active: false),
        actor(expired: true),
        actor(deadline: false),
        actor(user: 'other'),
        actor(member: 'other'),
        actor(farm: 'farm-b'),
      ]) {
        live = subject;
        await expectLater(
          service.listByOrganization('farm-a'),
          throwsStateError,
        );
        await expectLater(create(service), throwsStateError);
      }
      expect(store.reads, 0);
      expect(store.creates, 0);
    },
  );

  test('view revoked during storage read does not return documents', () async {
    store.onRead = () {
      live = actor(permissions: {});
    };
    await expectLater(service.listByOrganization('farm-a'), throwsStateError);
  });

  test(
    'report revoked during report preparation never reaches file writer',
    () async {
      store.onRead = () {
        live = actor(permissions: {PermissionCodes.financeView});
      };
      var writes = 0;
      await expectLater(
        service.exportReport(
          save: (_) async {
            writes++;
          },
        ),
        throwsStateError,
      );
      expect(writes, 0);
    },
  );

  test('repository returning a foreign document is rejected', () async {
    store.documents.add(
      FinanceDocument(
        id: 'foreign',
        organizationId: 'farm-b',
        code: 'CHI-1',
        kind: BusinessDocumentKind.payment,
        occurredAt: DateTime(2026),
        amountMinor: 100,
        currency: 'LAK',
        category: 'category',
      ),
    );
    await expectLater(service.listByOrganization('farm-a'), throwsStateError);
  });
}

class _Store implements FinanceDocumentStore {
  final documents = <FinanceDocument>[];
  int creates = 0;
  int reads = 0;
  void Function()? onRead;
  @override
  Future<List<FinanceDocument>> listByOrganization(
    String organizationId,
  ) async {
    reads++;
    onRead?.call();
    return List.of(documents);
  }

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
    creates++;
    final document = FinanceDocument(
      id: id,
      organizationId: organizationId,
      code: 'CHI-1',
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
}
