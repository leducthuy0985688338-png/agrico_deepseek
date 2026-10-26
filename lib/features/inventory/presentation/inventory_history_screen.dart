import 'dart:math';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import '../../../services/report_file_saver.dart';
import '../application/inventory_report.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/permissions/authorization.dart';
import '../application/inventory_service.dart';
import '../domain/entities/inventory_item.dart';

class InventoryHistoryScreen extends StatefulWidget {
  const InventoryHistoryScreen({
    super.key,
    required this.subject,
    required this.service,
    this.saveReport,
    this.warehouseId,
  });
  final AuthorizationSubject subject;
  final String? warehouseId;
  final InventoryService service;
  final Future<void> Function(Excel, String)? saveReport;

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  late Future<(List<InventoryItem>, List<InventoryMovement>)> data;
  final search = TextEditingController();
  String itemFilter = 'all';
  String kindFilter = 'all';
  DateTimeRange? period;
  bool exporting = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> export(InventoryReport report) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      widget.service.exportPermission(
        widget.subject,
        warehouseId: widget.warehouseId,
      );
      final stamp = widget.service.access.stamp(widget.subject);
      final (items, movements) = await load();
      widget.service.access.requireStamp(widget.subject, stamp);
      final workbook =
          InventoryReport(
            items: items,
            movements: movements,
            warehouseId: widget.warehouseId,
          ).workbook(
            query: search.text,
            itemId: itemFilter == 'all' ? null : itemFilter,
            kind: kindFilter == 'all'
                ? null
                : InventoryMovementKind.values.byName(kindFilter),
            from: period?.start,
            to: period?.end,
          );
      widget.service.exportPermission(
        widget.subject,
        warehouseId: widget.warehouseId,
      );
      await (widget.saveReport ?? saveExcelFile)(
        workbook,
        'AGRICO-Inventory-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.xlsx',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('inventory.exportFailed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<(List<InventoryItem>, List<InventoryMovement>)> load() async {
    final stamp = widget.service.access.stamp(widget.subject);
    final items = await widget.service.list(
      widget.subject,
      warehouseId: widget.warehouseId,
    );
    final movements = await widget.service.movements(
      widget.subject,
      warehouseId: widget.warehouseId,
    );
    final sorted = [...movements]
      ..sort((a, b) {
        final date = b.occurredAt.compareTo(a.occurredAt);
        return date != 0 ? date : b.id.compareTo(a.id);
      });
    widget.service.access.requireStamp(widget.subject, stamp);
    return (items, sorted);
  }

  @override
  void initState() {
    super.initState();
    data = load();
  }

  void reload() {
    setState(() {
      data = load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('inventory.history')),
        actions: [
          IconButton(
            key: const Key('inventory-history-refresh'),
            onPressed: reload,
            tooltip: l10n.text('common.retry'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<(List<InventoryItem>, List<InventoryMovement>)>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('inventory.loadFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (items, movements) = snapshot.data!;
          final report = InventoryReport(
            items: items,
            movements: movements,
            warehouseId: widget.warehouseId,
          );
          final filtered = report.filter(
            query: search.text,
            itemId: itemFilter == 'all' ? null : itemFilter,
            kind: kindFilter == 'all'
                ? null
                : InventoryMovementKind.values.byName(kindFilter),
            from: period?.start,
            to: period?.end,
          );
          final byId = {for (final item in items) item.id: item};
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  key: const Key('inventory-history-search'),
                  controller: search,
                  decoration: InputDecoration(
                    labelText: l10n.text('common.search'),
                    suffixIcon: IconButton(
                      onPressed: () {
                        search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  DropdownButton<String>(
                    key: const Key('inventory-history-item'),
                    value: itemFilter,
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(l10n.text('inventory.allItems')),
                      ),
                      ...items.map(
                        (i) =>
                            DropdownMenuItem(value: i.id, child: Text(i.code)),
                      ),
                    ],
                    onChanged: (v) => setState(() => itemFilter = v ?? 'all'),
                  ),
                  DropdownButton<String>(
                    key: const Key('inventory-history-kind'),
                    value: kindFilter,
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(l10n.text('inventory.allTypes')),
                      ),
                      DropdownMenuItem(
                        value: 'receipt',
                        child: Text(l10n.text('inventory.receipt')),
                      ),
                      DropdownMenuItem(
                        value: 'issue',
                        child: Text(l10n.text('inventory.issue')),
                      ),
                    ],
                    onChanged: (v) => setState(() => kindFilter = v ?? 'all'),
                  ),
                  TextButton(
                    key: const Key('inventory-history-period'),
                    onPressed: () async {
                      final result = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDateRange: period,
                      );
                      if (result != null && mounted) {
                        setState(() => period = result);
                      }
                    },
                    child: Text(
                      period == null
                          ? l10n.text('inventory.dateRange')
                          : '${period!.start.toIso8601String().substring(0, 10)} – ${period!.end.toIso8601String().substring(0, 10)}',
                    ),
                  ),
                  TextButton(
                    key: const Key('inventory-history-clear'),
                    onPressed: () => setState(() {
                      search.clear();
                      itemFilter = 'all';
                      kindFilter = 'all';
                      period = null;
                    }),
                    child: Text(l10n.text('inventory.clearFilters')),
                  ),
                  if ([
                    PermissionCodes.inventoryView,
                    PermissionCodes.reportOperations,
                    PermissionCodes.dataExport,
                  ].every(
                    (p) => widget.warehouseId == null
                        ? widget.service.can(widget.subject, p)
                        : widget.service.canAtWarehouse(
                            widget.subject,
                            p,
                            widget.warehouseId!,
                          ),
                  ))
                    TextButton(
                      key: const Key('inventory-history-export'),
                      onPressed: exporting ? null : () => export(report),
                      child: Text(
                        exporting ? l10n.text('inventory.exporting') : 'Excel',
                      ),
                    ),
                ],
              ),
              Text('${filtered.length} / ${movements.length}'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(l10n.text('inventory.stockReportNote')),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final movement = filtered[index];
                    final item = byId[movement.itemId];
                    final date = movement.occurredAt.toUtc().add(
                      const Duration(hours: 7),
                    );
                    String two(int value) => value.toString().padLeft(2, '0');
                    final stamp =
                        '${two(date.day)}/${two(date.month)}/${date.year} '
                        '${two(date.hour)}:${two(date.minute)} (UTC+7)';
                    final receipt =
                        movement.kind == InventoryMovementKind.receipt;
                    return ListTile(
                      key: Key('inventory-history-${movement.id}'),
                      leading: Icon(
                        receipt ? Icons.arrow_downward : Icons.arrow_upward,
                      ),
                      title: Text(
                        movement.code ?? l10n.text('inventory.noDocumentCode'),
                      ),
                      subtitle: Text(
                        '${item == null ? movement.itemId : '${item.code} · ${item.name}'}\n'
                        '${l10n.text('inventory.${movement.kind.name}')}: '
                        '${movement.quantity} ${item?.unit ?? ''}\n$stamp',
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
