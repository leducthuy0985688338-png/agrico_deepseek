import '../../../core/permissions/authorization.dart';
import '../domain/entities/parcel_work.dart';
import 'parcel_work_service.dart';
import 'parcel_work_time_productivity.dart';

/// Authorized, read-only calculation from existing parcel-work events.
/// Time evidence must be provided by a trusted caller; it is not persisted here.
extension ParcelWorkTimeReportRead on ParcelWorkService {
  Future<ParcelWorkTimeProductivity> recordedTimeReport(
    AuthorizationSubject subject, {
    required String parcelId,
    required ParcelWorkPhase phase,
    required Iterable<WorkTimeEvidence> timeEvidence,
  }) async {
    final records = await events(subject, parcelId);
    return const ParcelWorkTimeProductivityCalculator().summarize(
      farmId: subject.farmId,
      parcelId: parcelId,
      phase: phase,
      events: records,
      timeEvidence: timeEvidence,
    );
  }
}

/// CSV is an interim Excel-compatible export, not XLSX or Report20.
/// Rates describe recorded area, not geometry-verified unique area.
class ParcelWorkTimeReportCsv {
  const ParcelWorkTimeReportCsv();

  String encode(ParcelWorkTimeProductivity value) {
    final recorded = value.recorded;
    final columns = <String>[
      'farm_id',
      'parcel_id',
      'phase',
      'event_count',
      'recorded_area_m2',
      'events_without_area',
      'worker_minutes',
      'machine_minutes',
      'evidence_count',
      'recorded_ha_per_worker_hour',
      'recorded_ha_per_machine_hour',
    ];
    final values = <String>[
      recorded.farmId,
      recorded.parcelId,
      recorded.phase.name,
      '${recorded.eventCount}',
      '${recorded.recordedAreaM2}',
      '${recorded.eventsWithoutArea}',
      '${value.workerMinutes}',
      '${value.machineMinutes}',
      '${value.evidenceCount}',
      value.recordedHaPerWorkerHour?.toString() ?? '',
      value.recordedHaPerMachineHour?.toString() ?? '',
    ];
    return '\uFEFF${columns.map(_cell).join(',')}\r\n'
        '${values.map(_cell).join(',')}\r\n';
  }

  String _cell(String value) {
    // Protect Excel-compatible exports from formula injection, including
    // formula prefixes following leading whitespace and control characters.
    final trimmed = value.replaceFirst(RegExp(r'^[\s\u0000-\u001f]+'), '');
    final unsafe = trimmed.isNotEmpty && '=+-@'.contains(trimmed[0]);
    final safe = unsafe ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }
}
