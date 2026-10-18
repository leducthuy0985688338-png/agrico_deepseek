import 'package:excel/excel.dart';
import '../domain/entities/inventory_item.dart';

/// A read-only snapshot; stock remains authoritative in the repository.
class InventoryReport {
  const InventoryReport({required this.items, required this.movements});
  final List<InventoryItem> items;
  final List<InventoryMovement> movements;

  List<InventoryMovement> filter({
    String query = '',
    String? itemId,
    InventoryMovementKind? kind,
    DateTime? from,
    DateTime? to,
  }) {
    final normalized = query.trim().toLowerCase();
    final byId = {for (final item in items) item.id: item};
    return movements
        .where((movement) {
          if (itemId != null && movement.itemId != itemId) return false;
          if (kind != null && movement.kind != kind) return false;
          final local = movement.occurredAt.toUtc().add(
            const Duration(hours: 7),
          );
          final day = DateTime.utc(local.year, local.month, local.day);
          if (from != null &&
              day.isBefore(DateTime.utc(from.year, from.month, from.day))) {
            return false;
          }
          if (to != null &&
              day.isAfter(DateTime.utc(to.year, to.month, to.day))) {
            return false;
          }
          if (normalized.isEmpty) return true;
          final item = byId[movement.itemId];
          return [
            movement.code ?? '',
            movement.id,
            item?.code ?? '',
            item?.name ?? '',
            item?.supplier ?? '',
          ].any((value) => value.toLowerCase().contains(normalized));
        })
        .toList(growable: false);
  }

  /// Opening balance = current stock minus all historical receipts plus issues.
  /// This keeps reporting read-only even when date filters are applied.
  Excel workbook({
    String query = '',
    String? itemId,
    InventoryMovementKind? kind,
    DateTime? from,
    DateTime? to,
  }) {
    final selected = filter(
      query: query,
      itemId: itemId,
      kind: kind,
      from: from,
      to: to,
    );
    final excel = Excel.createExcel();
    final overview = excel['Overview'];
    overview.appendRow([
      TextCellValue('Farm inventory'),
      TextCellValue('Read-only report'),
    ]);
    overview.appendRow([
      TextCellValue('Stock totals scope'),
      TextCellValue(
        'Date range and item only; search and movement type apply to Movements sheet',
      ),
    ]);
    overview.appendRow([
      TextCellValue('Documents'),
      IntCellValue(selected.length),
    ]);
    overview.appendRow([TextCellValue('Search'), TextCellValue(query)]);
    overview.appendRow([
      TextCellValue('Item ID'),
      TextCellValue(itemId ?? 'All'),
    ]);
    overview.appendRow([
      TextCellValue('Movement type'),
      TextCellValue(kind?.name ?? 'All'),
    ]);
    overview.appendRow([
      TextCellValue('From'),
      TextCellValue(from?.toIso8601String().substring(0, 10) ?? 'All'),
    ]);
    overview.appendRow([
      TextCellValue('To'),
      TextCellValue(to?.toIso8601String().substring(0, 10) ?? 'All'),
    ]);
    final detail = excel['Movements'];
    detail.appendRow(
      [
        'Code',
        'Date UTC',
        'Item code',
        'Item name',
        'Type',
        'Quantity',
        'Unit',
      ].map(TextCellValue.new).toList(),
    );
    final byId = {for (final item in items) item.id: item};
    for (final movement in selected) {
      final item = byId[movement.itemId];
      detail.appendRow([
        TextCellValue(movement.code ?? ''),
        TextCellValue(movement.occurredAt.toUtc().toIso8601String()),
        TextCellValue(item?.code ?? movement.itemId),
        TextCellValue(item?.name ?? ''),
        TextCellValue(movement.kind.name),
        IntCellValue(movement.quantity),
        TextCellValue(item?.unit ?? ''),
      ]);
    }
    final stock = excel['Stock'];
    stock.appendRow(
      [
        'Item code',
        'Name',
        'Unit',
        'Opening',
        'Receipts',
        'Issues',
        'Closing',
        'Current',
      ].map(TextCellValue.new).toList(),
    );
    for (final item in items.where(
      (item) => itemId == null || item.id == itemId,
    )) {
      final all = movements.where((m) => m.itemId == item.id);
      final opening =
          item.stock -
          all.fold<int>(
            0,
            (sum, m) =>
                sum +
                (m.kind == InventoryMovementKind.receipt
                    ? m.quantity
                    : -m.quantity),
          );
      final before = all.where(
        (m) =>
            from != null &&
            DateTime.utc(
              m.occurredAt.toUtc().add(const Duration(hours: 7)).year,
              m.occurredAt.toUtc().add(const Duration(hours: 7)).month,
              m.occurredAt.toUtc().add(const Duration(hours: 7)).day,
            ).isBefore(DateTime.utc(from.year, from.month, from.day)),
      );
      final periodOpening =
          opening +
          before.fold<int>(
            0,
            (sum, m) =>
                sum +
                (m.kind == InventoryMovementKind.receipt
                    ? m.quantity
                    : -m.quantity),
          );
      // Stock summary is date-based, independent of search and type filters.
      final inPeriod = all.where((m) {
        final local = m.occurredAt.toUtc().add(const Duration(hours: 7));
        final day = DateTime.utc(local.year, local.month, local.day);
        return (from == null ||
                !day.isBefore(DateTime.utc(from.year, from.month, from.day))) &&
            (to == null ||
                !day.isAfter(DateTime.utc(to.year, to.month, to.day)));
      });
      final receipts = inPeriod
          .where((m) => m.kind == InventoryMovementKind.receipt)
          .fold<int>(0, (sum, m) => sum + m.quantity);
      final issues = inPeriod
          .where((m) => m.kind == InventoryMovementKind.issue)
          .fold<int>(0, (sum, m) => sum + m.quantity);
      stock.appendRow([
        TextCellValue(item.code),
        TextCellValue(item.name),
        TextCellValue(item.unit),
        IntCellValue(periodOpening),
        IntCellValue(receipts),
        IntCellValue(issues),
        IntCellValue(periodOpening + receipts - issues),
        IntCellValue(item.stock),
      ]);
    }
    return excel;
  }
}
