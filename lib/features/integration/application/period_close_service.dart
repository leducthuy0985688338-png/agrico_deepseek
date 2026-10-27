import '../../../core/permissions/authorization.dart';
import '../../../core/permissions/live_authorization.dart';
import '../domain/period_close.dart';
import 'integration_service.dart';

class PeriodCloseService {
  const PeriodCloseService({required this.repository, required this.access});
  final PeriodCloseStore repository;
  final IntegrationService access;
  bool get canClose =>
      access.canView &&
      access.can(PermissionCodes.financeApprove) &&
      access.can(PermissionCodes.auditReview);
  bool get canReopen => canClose && access.can(PermissionCodes.financeCorrect);
  Future<PeriodReview> review(String period) async {
    access.readAccess();
    final live = LiveAuthorization(access.currentSubject);
    final stamp = live.stamp(access.subject);
    final result = await repository.review(access.subject.farmId, period);
    live.requireStamp(access.subject, stamp);
    access.readAccess();
    return result;
  }

  void Function() guard(bool reopening) {
    if (!(reopening ? canReopen : canClose)) {
      throw StateError('Period approval permission denied.');
    }
    final live = LiveAuthorization(access.currentSubject);
    final stamp = live.stamp(access.subject);
    return () {
      live.requireStamp(access.subject, stamp);
      if (!(reopening ? canReopen : canClose)) {
        throw StateError('Period approval permission denied.');
      }
    };
  }

  Future<void> close(PeriodReview review, String reason) => repository.close(
    access.subject.farmId,
    review.period,
    review.token,
    review.revision,
    reason,
    access.subject.userId,
    guard(false),
  );
  Future<void> reopen(PeriodReview review, String reason) => repository.reopen(
    access.subject.farmId,
    review.period,
    review.revision,
    reason,
    access.subject.userId,
    guard(true),
  );
}
