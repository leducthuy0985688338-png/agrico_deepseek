import 'package:agrico_deepseek/features/farm/application/parcel_work_productivity.dart';
import 'package:agrico_deepseek/features/farm/application/parcel_work_productivity_export.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/parcel_work.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'exports recorded summary and resource participation without multiplying area',
    () {
      final summary = const ParcelWorkProductivityCalculator().summarize(
        farmId: 'farm',
        parcelId: 'parcel',
        phase: ParcelWorkPhase.clearing,
        events: [
          ParcelWorkEvent(
            id: 'e1',
            farmId: 'farm',
            parcelId: 'parcel',
            phase: ParcelWorkPhase.clearing,
            description: 'Clearing',
            occurredAt: DateTime.utc(2026),
            actorMembershipId: 'member',
            machineIds: ['machine'],
            workerIds: ['worker'],
            areaM2: 10000,
          ),
        ],
      );
      final csv = const ParcelWorkProductivityCsv().encode(summary);
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(
        csv,
        contains(
          '"summary","farm","parcel","clearing","","1","10000.0","1.0","0"',
        ),
      );
      expect(csv, contains('"worker_participation"'));
      expect(csv, contains('"machine_participation"'));
      expect(csv.split('10000.0').length - 1, 1);
    },
  );

  test(
    'escapes formulas, quotes and commas in untrusted resource identifiers',
    () {
      final summary = ParcelWorkProductivity(
        farmId: 'farm',
        parcelId: 'parcel',
        phase: ParcelWorkPhase.cultivation,
        eventCount: 1,
        recordedAreaM2: 0,
        eventsWithoutArea: 1,
        workerEventCounts: {'=1+2': 1, 'a,"b': 1},
        machineEventCounts: {},
      );
      final csv = const ParcelWorkProductivityCsv().encode(summary);
      expect(csv, contains('"\'=1+2"'));
      expect(csv, contains('"a,""b"'));
      expect(csv, contains('"1"'));
    },
  );
}
