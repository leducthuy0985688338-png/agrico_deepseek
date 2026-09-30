import 'package:agrico_deepseek/core/identity/domain/production_parcel_reference_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('block and plot codes use the approved production hierarchy', () {
    final block = ProductionParcelReferenceCode.landBlock(
      projectCode: 'AGR-NONG',
      landBlockNumber: 1,
    );
    final plot = ProductionParcelReferenceCode.fieldPlot(
      parent: block,
      number: 2,
    );
    expect(block.toString(), 'AGR-NONG-L001');
    expect(plot.toString(), 'AGR-NONG-L001-T002');
    expect(plot.projectCode, block.projectCode);
    expect(plot.landBlockNumber, block.landBlockNumber);
  });

  test('number width expands beyond 999 without truncation', () {
    final block = ProductionParcelReferenceCode.landBlock(
      projectCode: 'AGR-NONG',
      landBlockNumber: 1000,
    );
    expect(
      ProductionParcelReferenceCode.fieldPlot(
        parent: block,
        number: 1001,
      ).toString(),
      'AGR-NONG-L1000-T1001',
    );
  });

  test('rejects ambiguous project prefixes and nonpositive numbers', () {
    for (final project in [
      '',
      'agr-nong',
      ' AGR-NONG',
      'AGR--NONG',
      'AGR-NONG-L001',
      'AGR-NONG-T001',
    ]) {
      expect(
        () => ProductionParcelReferenceCode.landBlock(
          projectCode: project,
          landBlockNumber: 1,
        ),
        throwsFormatException,
      );
    }
    for (final number in [0, -1]) {
      expect(
        () => ProductionParcelReferenceCode.landBlock(
          projectCode: 'AGR-NONG',
          landBlockNumber: number,
        ),
        throwsFormatException,
      );
      expect(
        () => ProductionParcelReferenceCode.fieldPlot(
          parent: ProductionParcelReferenceCode.landBlock(
            projectCode: 'AGR-NONG',
            landBlockNumber: 1,
          ),
          number: number,
        ),
        throwsFormatException,
      );
    }
  });

  test('a plot cannot act as the parent of another plot', () {
    final block = ProductionParcelReferenceCode.landBlock(
      projectCode: 'AGR-NONG',
      landBlockNumber: 1,
    );
    final plot = ProductionParcelReferenceCode.fieldPlot(
      parent: block,
      number: 1,
    );
    expect(
      () => ProductionParcelReferenceCode.fieldPlot(parent: plot, number: 2),
      throwsFormatException,
    );
  });
}
