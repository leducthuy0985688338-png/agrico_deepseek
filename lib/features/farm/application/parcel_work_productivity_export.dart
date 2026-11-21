import '../../../core/permissions/authorization.dart';
import 'parcel_work_productivity.dart';
import 'parcel_work_service.dart';
import '../domain/entities/parcel_work.dart';

/// Read-only bridge: authorization is enforced by ParcelWorkService.events.
/// This does not approve area, detect polygon overlap, or infer hours worked.
extension ParcelWorkProductivityRead on ParcelWorkService {
  Future<ParcelWorkProductivity> recordedProductivity(
    AuthorizationSubject subject, {
    required String parcelId,
    required ParcelWorkPhase phase,
  }) async {
    final records = await events(subject, parcelId);
    return const ParcelWorkProductivityCalculator().summarize(
      farmId: subject.farmId,
      parcelId: parcelId,
      phase: phase,
      events: records,
    );
  }
}

/// Excel-compatible UTF-8 CSV for a *recorded* summary only.
/// Not a replacement for the Report20 XLSX contract.
class ParcelWorkProductivityCsv {
  const ParcelWorkProductivityCsv();

  String encode(ParcelWorkProductivity result) {
    final lines = <String>[
      'record_type,farm_id,parcel_id,phase,resource_id,event_count,recorded_area_m2,recorded_area_ha,events_without_area',
      _row([
        'summary',
        result.farmId,
        result.parcelId,
        result.phase.name,
        '',
        '${result.eventCount}',
        '${result.recordedAreaM2}',
        '${result.recordedAreaHa}',
        '${result.eventsWithoutArea}',
      ]),
    ];
    final workers = result.workerEventCounts.keys.toList()..sort();
    final machines = result.machineEventCounts.keys.toList()..sort();
    for (final id in workers) {
      lines.add(
        _row([
          'worker_participation',
          result.farmId,
          result.parcelId,
          result.phase.name,
          id,
          '${result.workerEventCounts[id]}',
          '',
          '',
          '',
        ]),
      );
    }
    for (final id in machines) {
      lines.add(
        _row([
          'machine_participation',
          result.farmId,
          result.parcelId,
          result.phase.name,
          id,
          '${result.machineEventCounts[id]}',
          '',
          '',
          '',
        ]),
      );
    }
    return '\uFEFF${lines.join('\r\n')}\r\n';
  }

  String _row(List<String> fields) => fields.map(_cell).join(',');

  String _cell(String value) {
    // Spreadsheet formula injection protection, including leading whitespace.
    final trimmed = value.trimLeft();
    final unsafe = trimmed.isNotEmpty && '=+-@'.contains(trimmed[0]);
    final safe = unsafe ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }
}
