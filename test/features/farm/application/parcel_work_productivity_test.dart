import 'package:agrico_deepseek/features/farm/application/parcel_work_productivity.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:flutter_test/flutter_test.dart';

ParcelWorkEvent work(
  String id, {
  String farmId = 'farm-1',
  String parcelId = 'parcel-1',
  ParcelWorkPhase phase = ParcelWorkPhase.clearing,
  double? area = 500,
  List<String> workers = const ['worker-1', 'worker-2'],
  List<String> machines = const ['machine-1'],
}) => ParcelWorkEvent(
  id: id,
  farmId: farmId,
  parcelId: parcelId,
  phase: phase,
  description: 'Field operation',
  occurredAt: DateTime.utc(2026, 11, 20),
  actorMembershipId: 'member-1',
  machineIds: machines,
  workerIds: workers,
  areaM2: area,
);

void main() {
  const calculator = ParcelWorkProductivityCalculator();
  ParcelWorkProductivity summarize(List<ParcelWorkEvent> events) =>
      calculator.summarize(
        farmId: 'farm-1',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.clearing,
        events: events,
      );

  test('records area once per event, not once per resource', () {
    final result = summarize([work('one'), work('two', area: 1500)]);
    expect(result.recordedAreaM2, 2000);
    expect(result.recordedAreaHa, 0.2);
    expect(result.eventCount, 2);
    expect(result.workerEventCounts['worker-1'], 2);
    expect(result.workerEventCounts['worker-2'], 2);
    expect(result.machineEventCounts['machine-1'], 2);
  });

  test('keeps missing area explicit and filters phase', () {
    final result = summarize([
      work('one', area: null),
      work('two', phase: ParcelWorkPhase.cultivation, area: 300),
    ]);
    expect(result.eventCount, 1);
    expect(result.eventsWithoutArea, 1);
    expect(result.recordedAreaM2, 0);
  });

  test('rejects cross-farm and cross-parcel data', () {
    expect(() => summarize([work('a', farmId: 'other')]), throwsStateError);
    expect(() => summarize([work('a', parcelId: 'other')]), throwsStateError);
  });

  test('rejects duplicate event IDs, even across phases', () {
    expect(
      () => summarize([
        work('same'),
        work('same', phase: ParcelWorkPhase.cultivation),
      ]),
      throwsStateError,
    );
  });

  test('rejects invalid area and blank scope', () {
    expect(
      () => summarize([work('bad', area: double.nan)]),
      throwsFormatException,
    );
    expect(
      () => calculator.summarize(
        farmId: '',
        parcelId: 'parcel-1',
        phase: ParcelWorkPhase.clearing,
        events: [],
      ),
      throwsFormatException,
    );
  });
}
