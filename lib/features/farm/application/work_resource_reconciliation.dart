import '../../../models/employee_model.dart';
import '../../../models/machine_model.dart';
import '../../../core/permissions/authorization.dart';
import '../domain/entities/parcel_work.dart';
import 'parcel_work_service.dart';

/// A read-only comparison. Provider sample entries must never be passed as
/// real inventory merely because they exist in memory at app startup.
class WorkResourceReconciliation {
  const WorkResourceReconciliation(this.work);

  final ParcelWorkService work;

  Future<WorkResourceComparison> compare(
    AuthorizationSubject subject, {
    required List<MachineModel> verifiedMachines,
    required List<EmployeeModel> verifiedEmployees,
  }) async {
    final existing = await work.resources(subject);
    final candidates = <WorkResource>[
      for (final machine in verifiedMachines)
        WorkResource(
          id: 'legacy-machine:${machine.id}', farmId: subject.farmId,
          kind: WorkResourceKind.machine, code: machine.id,
          name: machine.name,
        ),
      for (final employee in verifiedEmployees)
        WorkResource(
          id: 'legacy-worker:${employee.id}', farmId: subject.farmId,
          kind: WorkResourceKind.worker, code: employee.id,
          name: employee.name, active: employee.isActive,
        ),
    ];
    final byId = {for (final resource in existing) resource.id: resource};
    final byCode = {
      for (final resource in existing)
        (resource.kind, resource.code): resource,
    };
    final ready = <WorkResource>[];
    final matched = <WorkResource>[];
    final conflicts = <WorkResource>[];
    final counts = <(WorkResourceKind, String), int>{};
    for (final candidate in candidates) {
      final key = (candidate.kind, candidate.code);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    for (final candidate in candidates) {
      candidate.validate();
      final key = (candidate.kind, candidate.code);
      final idMatch = byId[candidate.id];
      final codeMatch = byCode[key];
      final existingMatch = idMatch ?? codeMatch;
      if (counts[key]! > 1 ||
          (idMatch != null &&
              (idMatch.kind != candidate.kind || idMatch.code != candidate.code)) ||
          (codeMatch != null && codeMatch.id != candidate.id) ||
          (existingMatch != null &&
              (existingMatch.name != candidate.name ||
                  existingMatch.active != candidate.active))) {
        conflicts.add(candidate);
      } else if (idMatch != null) {
        matched.add(candidate);
      } else {
        ready.add(candidate);
      }
    }
    return WorkResourceComparison(
      ready: List.unmodifiable(ready), matched: List.unmodifiable(matched),
      conflicts: List.unmodifiable(conflicts),
    );
  }
}

class WorkResourceComparison {
  const WorkResourceComparison({
    required this.ready, required this.matched, required this.conflicts,
  });

  final List<WorkResource> ready;
  final List<WorkResource> matched;
  final List<WorkResource> conflicts;
}
