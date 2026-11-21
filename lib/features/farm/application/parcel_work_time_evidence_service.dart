import '../../../core/permissions/authorization.dart';
import '../data/local/sqlite_parcel_work_time_evidence_repository.dart';
import '../domain/entities/parcel_work.dart';
import 'parcel_work_service.dart';
import 'parcel_work_time_productivity.dart';

/// Checks authorization and assignments before accessing the SQLite store.
class ParcelWorkTimeEvidenceService {
  const ParcelWorkTimeEvidenceService(this.work, this.store);
  final ParcelWorkService work;
  final SqliteParcelWorkTimeEvidenceRepository store;

  Future<void> record(
    AuthorizationSubject subject, {
    required String parcelId,
    required WorkTimeEvidence evidence,
  }) async {
    if (!subject.dataScopes.contains(DataScope.allFarm) ||
        !const AuthorizationService().can(
          subject: subject,
          permission: PermissionCodes.fieldEdit,
          resource: ResourceContext(farmId: subject.farmId, fieldId: parcelId),
        )) {
      throw StateError('Work time write denied.');
    }
    final events = await work.events(subject, parcelId);
    final matching = events.where((e) => e.id == evidence.eventId).toList();
    if (matching.length != 1) throw StateError('Work event not found.');
    final assigned = evidence.kind == WorkTimeResourceKind.worker
        ? matching.single.workerIds
        : matching.single.machineIds;
    if (!assigned.contains(evidence.resourceId)) {
      throw StateError('Resource not assigned to work event.');
    }
    await store.record(
      farmId: subject.farmId,
      parcelId: parcelId,
      actorMembershipId: subject.membershipId,
      evidence: evidence,
    );
  }

  Future<List<WorkTimeEvidence>> read(
    AuthorizationSubject subject, {
    required String parcelId,
  }) async {
    final events = await work.events(subject, parcelId);
    final evidence = await store.read(
      farmId: subject.farmId,
      parcelId: parcelId,
    );
    final eventMap = {for (final event in events) event.id: event};
    for (final item in evidence) {
      final event = eventMap[item.eventId];
      if (event == null ||
          !(item.kind == WorkTimeResourceKind.worker
                  ? event.workerIds
                  : event.machineIds)
              .contains(item.resourceId)) {
        throw StateError('Invalid persisted time evidence.');
      }
    }
    return evidence;
  }

  Future<ParcelWorkTimeProductivity> report(
    AuthorizationSubject subject, {
    required String parcelId,
    required ParcelWorkPhase phase,
  }) async {
    final events = await work.events(subject, parcelId);
    final evidence = await read(subject, parcelId: parcelId);
    final ids = events.where((e) => e.phase == phase).map((e) => e.id).toSet();
    return const ParcelWorkTimeProductivityCalculator().summarize(
      farmId: subject.farmId,
      parcelId: parcelId,
      phase: phase,
      events: events.where((e) => e.phase == phase),
      timeEvidence: evidence.where((e) => ids.contains(e.eventId)),
    );
  }
}
