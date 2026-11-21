import 'parcel_work_productivity.dart';
import '../domain/entities/parcel_work.dart';

enum WorkTimeResourceKind { worker, machine }

/// Explicitly supplied time evidence. No duration is inferred from event dates.
class WorkTimeEvidence {
  const WorkTimeEvidence({
    required this.eventId,
    required this.resourceId,
    required this.kind,
    required this.minutes,
    required this.evidenceReference,
  });

  final String eventId;
  final String resourceId;
  final WorkTimeResourceKind kind;
  final int minutes;
  final String evidenceReference;
}

/// Rates are recorded-area indicators, NOT verified unique-area productivity.
/// The same recorded area is never assigned to individual workers or machines.
class ParcelWorkTimeProductivity {
  const ParcelWorkTimeProductivity({
    required this.recorded,
    required this.workerMinutes,
    required this.machineMinutes,
    required this.evidenceCount,
  });

  final ParcelWorkProductivity recorded;
  final int workerMinutes;
  final int machineMinutes;
  final int evidenceCount;

  double? get recordedHaPerWorkerHour =>
      workerMinutes == 0 || recorded.eventsWithoutArea != 0
      ? null
      : recorded.recordedAreaHa * 60 / workerMinutes;

  double? get recordedHaPerMachineHour =>
      machineMinutes == 0 || recorded.eventsWithoutArea != 0
      ? null
      : recorded.recordedAreaHa * 60 / machineMinutes;
}

class ParcelWorkTimeProductivityCalculator {
  const ParcelWorkTimeProductivityCalculator();

  ParcelWorkTimeProductivity summarize({
    required String farmId,
    required String parcelId,
    required ParcelWorkPhase phase,
    required Iterable<ParcelWorkEvent> events,
    required Iterable<WorkTimeEvidence> timeEvidence,
  }) {
    final eventList = events.toList();
    final recorded = const ParcelWorkProductivityCalculator().summarize(
      farmId: farmId,
      parcelId: parcelId,
      phase: phase,
      events: eventList,
    );
    final eventMap = {for (final e in eventList) e.id: e};
    final seen = <String>{};
    var workerMinutes = 0;
    var machineMinutes = 0;
    var count = 0;
    for (final item in timeEvidence) {
      if (item.eventId.trim().isEmpty ||
          item.resourceId.trim().isEmpty ||
          item.evidenceReference.trim().isEmpty ||
          item.minutes <= 0) {
        throw const FormatException('Invalid or unproven time evidence.');
      }
      final event = eventMap[item.eventId];
      if (event == null || event.phase != phase) {
        throw StateError('Time evidence does not match a selected work event.');
      }
      final assigned = item.kind == WorkTimeResourceKind.worker
          ? event.workerIds
          : event.machineIds;
      if (!assigned.contains(item.resourceId)) {
        throw StateError('Time evidence resource not assigned to event.');
      }
      final key =
          '${item.eventId}\u0000${item.kind.name}\u0000${item.resourceId}';
      if (!seen.add(key)) {
        throw StateError('Duplicate resource time evidence.');
      }
      if (item.kind == WorkTimeResourceKind.worker) {
        workerMinutes += item.minutes;
        if (workerMinutes > 2147483647) throw StateError('Time overflow.');
      } else {
        machineMinutes += item.minutes;
        if (machineMinutes > 2147483647) throw StateError('Time overflow.');
      }
      count++;
    }
    return ParcelWorkTimeProductivity(
      recorded: recorded,
      workerMinutes: workerMinutes,
      machineMinutes: machineMinutes,
      evidenceCount: count,
    );
  }
}
