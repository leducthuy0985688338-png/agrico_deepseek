import '../domain/entities/parcel_work.dart';

/// Read-only summary of recorded work. This is NOT approved productivity,
/// surveyed unique area, payroll, or evidence of non-overlapping polygons.
class ParcelWorkProductivity {
  const ParcelWorkProductivity({
    required this.farmId,
    required this.parcelId,
    required this.phase,
    required this.eventCount,
    required this.recordedAreaM2,
    required this.eventsWithoutArea,
    required this.workerEventCounts,
    required this.machineEventCounts,
  });

  final String farmId;
  final String parcelId;
  final ParcelWorkPhase phase;
  final int eventCount;
  final double recordedAreaM2;
  final int eventsWithoutArea;
  final Map<String, int> workerEventCounts;
  final Map<String, int> machineEventCounts;

  double get recordedAreaHa => recordedAreaM2 / 10000;
}

/// Summarizes *recorded* events without multiplying area by crew size.
/// No geometric overlap check is possible from ParcelWorkEvent alone.
class ParcelWorkProductivityCalculator {
  const ParcelWorkProductivityCalculator();

  ParcelWorkProductivity summarize({
    required String farmId,
    required String parcelId,
    required ParcelWorkPhase phase,
    required Iterable<ParcelWorkEvent> events,
  }) {
    if (farmId.trim().isEmpty || parcelId.trim().isEmpty) {
      throw const FormatException('Farm and parcel are required.');
    }
    final seenIds = <String>{};
    final workers = <String, int>{};
    final machines = <String, int>{};
    var area = 0.0;
    var count = 0;
    var missingArea = 0;
    for (final event in events) {
      event.validate();
      if (event.farmId != farmId || event.parcelId != parcelId) {
        throw StateError('Cross-scope work event rejected.');
      }
      if (!seenIds.add(event.id)) {
        throw StateError('Duplicate work event rejected.');
      }
      if (event.phase != phase) continue;
      count++;
      if (event.areaM2 == null) {
        missingArea++;
      } else {
        area += event.areaM2!;
        if (!area.isFinite) {
          throw StateError('Recorded area overflow.');
        }
      }
      for (final id in event.workerIds) {
        workers.update(id, (value) => value + 1, ifAbsent: () => 1);
      }
      for (final id in event.machineIds) {
        machines.update(id, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return ParcelWorkProductivity(
      farmId: farmId,
      parcelId: parcelId,
      phase: phase,
      eventCount: count,
      recordedAreaM2: area,
      eventsWithoutArea: missingArea,
      workerEventCounts: Map.unmodifiable(workers),
      machineEventCounts: Map.unmodifiable(machines),
    );
  }
}
