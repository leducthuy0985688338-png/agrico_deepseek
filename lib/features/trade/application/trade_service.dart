import '../../../core/permissions/authorization.dart';
import '../domain/trade.dart';
export '../domain/trade.dart';

class TradeService {
  const TradeService(
    this.repository, {
    required this.subject,
    required this.currentSubject,
  });
  final TradeRepository repository;
  final AuthorizationSubject subject;
  final AuthorizationSubject? Function() currentSubject;
  bool can(String permission) {
    final s = currentSubject();
    return s != null &&
        s.userId == subject.userId &&
        s.membershipId == subject.membershipId &&
        s.farmId == subject.farmId &&
        s.dataScopes.contains(DataScope.allFarm) &&
        const AuthorizationService().can(
          subject: s,
          permission: permission,
          resource: ResourceContext(farmId: s.farmId),
        );
  }

  void require(String permission) {
    if (!can(permission)) throw StateError('Trade permission denied.');
  }

  Future<List<T>> read<T>(
    Future<List<T>> Function() load,
    String permission,
  ) async {
    require(permission);
    final result = await load();
    require(permission);
    return result;
  }

  Future<List<TradeRecord>> documents() => read(
    () => repository.documents(subject.farmId),
    PermissionCodes.financeView,
  );
  Future<List<FinishedLot>> lots() =>
      read(() => repository.lots(subject.farmId), PermissionCodes.financeView);
  Future<List<TradePayment>> payments() => read(
    () => repository.payments(subject.farmId),
    PermissionCodes.financeView,
  );
  Future<List<Map<String, Object?>>> cashBook() =>
      read(() => repository.cashBook(subject.farmId), PermissionCodes.cashView);
  Future<List<Map<String, Object?>>> choices(String kind) => read(
    () => repository.choices(subject.farmId, kind),
    PermissionCodes.financeView,
  );
  Future<void> create(TradeDraft draft) {
    require(PermissionCodes.financeView);
    require(PermissionCodes.financeCreate);
    draft.validate();
    return repository.create(subject.farmId, draft, subject.userId);
  }

  Future<void> post(TradeRecord r) {
    require(PermissionCodes.financeView);
    require(PermissionCodes.financePost);
    require(PermissionCodes.financeApprove);
    if (r.draft.kind != TradeKind.expense) {
      require(PermissionCodes.inventoryPrice);
      require(
        r.draft.kind == TradeKind.sale
            ? PermissionCodes.inventoryIssue
            : PermissionCodes.inventoryReceive,
      );
    }
    return repository.post(
      subject.farmId,
      r.draft.id,
      r.revision,
      subject.userId,
    );
  }

  Future<void> voidDocument(TradeRecord r, String day, String reason) {
    require(PermissionCodes.financeCorrect);
    if (r.status == 'posted' && r.draft.kind != TradeKind.expense) {
      require(PermissionCodes.inventoryAdjust);
      require(PermissionCodes.inventoryPrice);
    }
    return repository.voidDocument(
      subject.farmId,
      r.draft.id,
      r.revision,
      day,
      reason,
      subject.userId,
    );
  }

  Future<void> settle({
    required String id,
    required String documentId,
    required String amount,
    required String currency,
    required String day,
    required String reference,
  }) {
    require(PermissionCodes.financeCreate);
    require(PermissionCodes.cashRecord);
    require(PermissionCodes.financeView);
    return repository.settle(
      subject.farmId,
      id,
      documentId,
      amount,
      currency,
      day,
      reference,
      subject.userId,
    );
  }

  Future<void> reversePayment(
    TradePayment p,
    String id,
    String day,
    String reason,
  ) {
    require(PermissionCodes.financeCorrect);
    require(PermissionCodes.cashRecord);
    require(PermissionCodes.financeView);
    return repository.reversePayment(
      subject.farmId,
      p.id,
      id,
      day,
      reason,
      subject.userId,
    );
  }

  void exportPermission() {
    require(PermissionCodes.financeView);
    require(PermissionCodes.cashView);
    require(PermissionCodes.reportFinance);
    require(PermissionCodes.dataExport);
  }
}
