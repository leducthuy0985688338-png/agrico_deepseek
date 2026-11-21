import 'package:agrico_deepseek/features/farm/application/parcel_work_time_productivity.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:flutter_test/flutter_test.dart';

ParcelWorkEvent event(String id, {double? area = 10000}) => ParcelWorkEvent(
  id: id,
  farmId: 'farm',
  parcelId: 'parcel',
  phase: ParcelWorkPhase.clearing,
  description: 'Field work',
  occurredAt: DateTime.utc(2026, 11, 20),
  actorMembershipId: 'member',
  workerIds: const ['w1', 'w2'],
  machineIds: const ['m1'],
  areaM2: area,
);

WorkTimeEvidence time(
  String eventId,
  String resourceId,
  WorkTimeResourceKind kind,
  int minutes, {
  String reference = 'timesheet-1',
}) => WorkTimeEvidence(
  eventId: eventId,
  resourceId: resourceId,
  kind: kind,
  minutes: minutes,
  evidenceReference: reference,
);

void main() {
  const calculator = ParcelWorkTimeProductivityCalculator();
  ParcelWorkTimeProductivity calculate(
    List<ParcelWorkEvent> events,
    List<WorkTimeEvidence> evidence,
  ) => calculator.summarize(
    farmId: 'farm',
    parcelId: 'parcel',
    phase: ParcelWorkPhase.clearing,
    events: events,
    timeEvidence: evidence,
  );

  test('computes recorded ha per worker-hour and machine-hour', () {
    final result = calculate(
      [event('e1')],
      [
        time('e1', 'w1', WorkTimeResourceKind.worker, 120),
        time('e1', 'w2', WorkTimeResourceKind.worker, 120),
        time('e1', 'm1', WorkTimeResourceKind.machine, 60),
      ],
    );
    expect(result.recorded.recordedAreaHa, 1);
    expect(result.recordedHaPerWorkerHour, 0.25);
    expect(result.recordedHaPerMachineHour, 1);
  });

  test('missing hours remain null rather than inferred', () {
    final result = calculate([event('e1')], []);
    expect(result.recordedHaPerWorkerHour, isNull);
    expect(result.recordedHaPerMachineHour, isNull);
  });

  test('missing area suppresses misleading productivity rate', () {
    final result = calculate(
      [event('e1', area: null)],
      [time('e1', 'w1', WorkTimeResourceKind.worker, 60)],
    );
    expect(result.recordedHaPerWorkerHour, isNull);
  });

  test('rejects duplicate, unassigned and unknown event evidence', () {
    final t = time('e1', 'w1', WorkTimeResourceKind.worker, 60);
    expect(() => calculate([event('e1')], [t, t]), throwsStateError);
    expect(
      () => calculate(
        [event('e1')],
        [time('e1', 'other', WorkTimeResourceKind.worker, 60)],
      ),
      throwsStateError,
    );
    expect(
      () => calculate(
        [event('e1')],
        [time('unknown', 'w1', WorkTimeResourceKind.worker, 60)],
      ),
      throwsStateError,
    );
  });

  test('rejects nonpositive minutes and missing evidence reference', () {
    expect(
      () => calculate(
        [event('e1')],
        [time('e1', 'w1', WorkTimeResourceKind.worker, 0)],
      ),
      throwsFormatException,
    );
    expect(
      () => calculate(
        [event('e1')],
        [time('e1', 'w1', WorkTimeResourceKind.worker, 60, reference: '')],
      ),
      throwsFormatException,
    );
  });
}
