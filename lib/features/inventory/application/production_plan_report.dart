import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:excel/excel.dart';

import '../domain/entities/exact_decimal.dart';
import '../domain/entities/production_plan.dart';
import '../domain/repositories/production_destination_repository.dart';

class ProductionPlanReport {
  const ProductionPlanReport({
    required this.farmId,
    required this.plans,
    required this.tasks,
    required this.costs,
    this.parcelId,
    this.planId,
    this.from,
    this.to,
  });
  final String farmId;
  final List<ProductionPlan> plans;
  final List<ProductionPlanTask> tasks;
  final List<ProductionMaterialCost> costs;
  final String? parcelId, planId;
  final DateTime? from, to;
  List<ProductionPlan> get selectedPlans => plans
      .where(
        (p) =>
            (parcelId == null || p.parcelId == parcelId) &&
            (planId == null || p.id == planId),
      )
      .toList();
  List<ProductionMaterialCost> get selectedCosts {
    final ids = selectedPlans.map((p) => p.id).toSet();
    return costs.where((c) {
      final day = c.occurredAt
          .toUtc()
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 10);
      return ids.contains(c.planId) &&
          (from == null ||
              day.compareTo(from!.toIso8601String().substring(0, 10)) >= 0) &&
          (to == null ||
              day.compareTo(to!.toIso8601String().substring(0, 10)) <= 0);
    }).toList();
  }

  ExactDecimal materialActual(String id) => selectedCosts
      .where((c) => c.planId == id)
      .fold(ExactDecimal.parse('0'), (sum, c) {
        if (c.amountText == null || c.currency == null) {
          throw StateError('Unpriced source cost.');
        }
        return sum + ExactDecimal.parse(c.amountText!);
      });
  Excel workbook() {
    if (from != null && to != null && from!.isAfter(to!)) {
      throw const FormatException('Invalid reporting dates.');
    }
    final selected = selectedPlans;
    final byId = {for (final p in selected) p.id: p};
    for (final c in selectedCosts) {
      if (c.currency != byId[c.planId]!.currency) {
        throw StateError('Cost currency mismatch.');
      }
    }
    final excel = Excel.createExcel();
    final meta = excel['THONG TIN'];
    void row(Sheet sheet, List<String> values, {Set<int> numbers = const {}}) {
      sheet.appendRow([
        for (var i = 0; i < values.length; i++)
          if (numbers.contains(i) &&
              values[i].replaceAll(RegExp(r'[-.]'), '').length <= 15)
            if (values[i].contains('.'))
              DoubleCellValue(double.parse(values[i]))
            else
              IntCellValue(int.parse(values[i]))
          else
            TextCellValue(values[i]),
      ]);
    }

    row(meta, [
      'AGRICO',
      'Kế hoạch và chi phí vật tư / Production plans and materials',
    ]);
    row(meta, ['Farm', farmId]);
    row(meta, ['Exported UTC', DateTime.now().toUtc().toIso8601String()]);
    row(meta, ['Business timezone', 'UTC+7']);
    row(meta, ['Parcel', parcelId ?? 'All']);
    row(meta, ['Plan', planId ?? 'All']);
    row(meta, ['From', from?.toIso8601String().substring(0, 10) ?? 'All']);
    row(meta, ['To', to?.toIso8601String().substring(0, 10) ?? 'All']);
    row(meta, [
      'Scope',
      'Budgets = entire plan; actual materials = selected posting period.',
    ]);
    row(meta, [
      'Money',
      'VND and LAK separately. Numeric cells up to 15 digits; longer exact decimals stored as text. No implicit FX or rounding.',
    ]);
    row(meta, [
      'Labor/machines',
      'Budgets only. Actual labor/machine accounting is not connected in this release.',
    ]);
    row(meta, [
      'Exclusions',
      'Material consumption excludes cash purchases/payments to prevent duplicate costs.',
    ]);
    final summary = excel['KE HOACH SAN XUAT'];
    row(summary, [
      'Code',
      'Plan ID',
      'Name',
      'Parcel ID',
      'Season ID',
      'Crop',
      'Start',
      'Planned end',
      'Status',
      'Currency',
      'Material budget',
      'Material actual in period',
      'Material variance actual-budget',
      'Labor hours planned',
      'Labor budget',
      'Machine shifts planned',
      'All-inclusive machine budget',
      'Total budget',
      'Labor actual',
      'Machine actual',
      'Tasks completed',
      'Tasks total',
      'Parcel code',
      'Season name',
    ]);
    for (final p in selected) {
      final actual = materialActual(p.id);
      final work = tasks.where((t) => t.planId == p.id);
      row(
        summary,
        [
          p.code ?? '',
          p.id,
          p.name,
          p.parcelId,
          p.seasonId,
          p.crop,
          p.startsOn,
          p.endsOn,
          p.status.name,
          p.currency,
          p.materialBudget,
          actual.toString(),
          (actual - ExactDecimal.parse(p.materialBudget)).toString(),
          p.laborHours,
          p.laborBudget,
          p.machineShifts,
          p.machineBudget,
          p.totalBudget.toString(),
          'Not connected',
          'Not connected',
          work.where((t) => t.completed).length.toString(),
          work.length.toString(),
          p.parcelCode ?? p.parcelId,
          p.seasonName ?? p.seasonId,
        ],
        numbers: {10, 11, 12, 13, 14, 15, 16, 17, 20, 21},
      );
    }
    final detail = excel['VAT TU SD'];
    row(detail, [
      'Laos date',
      'UTC timestamp',
      'Plan code',
      'Plan ID',
      'Parcel code',
      'Parcel ID',
      'Season',
      'Season ID',
      'Movement ID',
      'Item snapshot',
      'Quantity',
      'Unit',
      'Admin unit price',
      'Amount',
      'Currency',
    ]);
    for (final c in selectedCosts) {
      row(
        detail,
        [
          c.occurredAt
              .toUtc()
              .add(const Duration(hours: 7))
              .toIso8601String()
              .substring(0, 10),
          c.occurredAt.toUtc().toIso8601String(),
          c.planCode ?? '',
          c.planId ?? '',
          c.parcelCode,
          c.parcelId,
          c.seasonName,
          c.seasonId,
          c.movementId,
          c.itemName,
          c.quantity.toString(),
          c.unit,
          c.unitPriceText ?? '',
          c.amountText ?? '',
          c.currency ?? '',
        ],
        numbers: {10, 12, 13},
      );
    }
    final work = excel['LICH TAC VU'];
    row(work, [
      'Plan code',
      'Plan ID',
      'Task ID',
      'Stage',
      'Task',
      'Planned quantity',
      'Unit',
      'Completed',
    ]);
    for (final t in tasks.where((t) => byId.containsKey(t.planId))) {
      row(
        work,
        [
          byId[t.planId]!.code ?? '',
          t.planId,
          t.id,
          t.stage,
          t.title,
          t.quantity,
          t.unit,
          t.completed ? 'Yes' : 'No',
        ],
        numbers: {5},
      );
    }
    final totals = excel['TONG HOP'];
    row(totals, [
      'Currency',
      'Material budget',
      'Material actual in period',
      'Labor budget',
      'Machine budget',
      'Total budget',
    ]);
    for (final currency in ['VND', 'LAK']) {
      final group = selected.where((p) => p.currency == currency);
      ExactDecimal sum(String Function(ProductionPlan) value) => group.fold(
        ExactDecimal.parse('0'),
        (s, p) => s + ExactDecimal.parse(value(p)),
      );
      row(
        totals,
        [
          currency,
          sum((p) => p.materialBudget).toString(),
          group
              .fold(ExactDecimal.parse('0'), (s, p) => s + materialActual(p.id))
              .toString(),
          sum((p) => p.laborBudget).toString(),
          sum((p) => p.machineBudget).toString(),
          sum((p) => p.totalBudget.toString()).toString(),
        ],
        numbers: {1, 2, 3, 4, 5},
      );
    }
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet == 'Sheet1') {
      excel.delete(defaultSheet);
    }
    for (final sheet in excel.tables.values) {
      for (var col = 0; col < sheet.maxColumns; col++) {
        sheet.setColumnWidth(col, col == 0 ? 24 : 28);
      }
      sheet.setRowHeight(0, 36);
      if (sheet.maxRows > 0) {
        for (var col = 0; col < sheet.maxColumns; col++) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
              .cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.fromHexString('#DDEEDB'),
          );
        }
      }
    }
    return excel;
  }

  /// Add worksheet layout unsupported by the Excel author's public API.
  /// Operates only on this newly generated workbook, never user files.
  List<int> bytes() {
    final archive = ZipDecoder().decodeBytes(workbook().encode()!);
    XmlDocument read(String path) => XmlDocument.parse(
      utf8.decode(archive.findFile(path)!.content as List<int>),
    );
    final book = read('xl/workbook.xml');
    final rels = read('xl/_rels/workbook.xml.rels');
    final targets = {
      for (final r in rels.rootElement.childElements)
        r.getAttribute('Id'): r.getAttribute('Target')!,
    };
    final modified = <String, List<int>>{};
    for (final sheet in book.findAllElements('sheet')) {
      final target = targets[sheet.getAttribute('r:id')];
      if (target == null) continue;
      final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final document = read(path);
      final root = document.rootElement;
      root.children.removeWhere(
        (n) => n is XmlElement && n.name.local == 'sheetViews',
      );
      final views = XmlElement(XmlName('sheetViews'), [], [
        XmlElement(
          XmlName('sheetView'),
          [XmlAttribute(XmlName('workbookViewId'), '0')],
          [
            XmlElement(XmlName('pane'), [
              XmlAttribute(XmlName('ySplit'), '1'),
              XmlAttribute(XmlName('topLeftCell'), 'A2'),
              XmlAttribute(XmlName('activePane'), 'bottomLeft'),
              XmlAttribute(XmlName('state'), 'frozen'),
            ]),
          ],
        ),
      ]);
      final dimension = root.childElements
          .where((e) => e.name.local == 'dimension')
          .firstOrNull;
      root.children.insert(
        dimension == null ? 0 : root.children.indexOf(dimension) + 1,
        views,
      );
      if (sheet.getAttribute('name') != 'THONG TIN') {
        final range = dimension?.getAttribute('ref');
        if (range != null) {
          root.children.removeWhere(
            (n) => n is XmlElement && n.name.local == 'autoFilter',
          );
          final data = root.childElements.firstWhere(
            (e) => e.name.local == 'sheetData',
          );
          root.children.insert(
            root.children.indexOf(data) + 1,
            XmlElement(XmlName('autoFilter'), [
              XmlAttribute(XmlName('ref'), range),
            ]),
          );
        }
      }
      modified[path] = utf8.encode(document.toXmlString());
    }
    final out = Archive();
    for (final file in archive) {
      final data = modified[file.name] ?? file.content as List<int>;
      out.addFile(ArchiveFile(file.name, data.length, data));
    }
    return ZipEncoder().encode(out)!;
  }
}
