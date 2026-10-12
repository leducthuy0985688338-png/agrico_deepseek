import '../application/production_cost_period.dart';
import 'dart:math';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../application/production_cost_summary.dart';
import '../application/production_cost_report.dart';
import '../../../services/report_file_saver.dart';
import 'finance_amount_formatter.dart';

class ProductionCostsScreen extends StatefulWidget {
  const ProductionCostsScreen({
    super.key,
    required this.service,
    this.saveReport,
    this.pickPeriod,
  });
  final ProductionCostSummary service;
  final Future<DateTimeRange?> Function(BuildContext, DateTimeRange?)?
  pickPeriod;
  final Future<void> Function(Excel workbook, String fileName)? saveReport;
  @override
  State<ProductionCostsScreen> createState() => _ProductionCostsScreenState();
}

class _ProductionCostsScreenState extends State<ProductionCostsScreen> {
  ProductionCostPeriod period = const ProductionCostPeriod();
  late Future<ProductionCostSnapshot> data = widget.service.load(
    period: period,
  );

  Future<void> selectPeriod() async {
    final initial = period.from == null || period.to == null
        ? null
        : DateTimeRange(start: period.from!, end: period.to!);
    final selected = widget.pickPeriod != null
        ? await widget.pickPeriod!(context, initial)
        : await showDateRangePicker(
            context: context,
            firstDate: DateTime(1900),
            lastDate: DateTime(2100, 12, 31),
            initialDateRange: initial,
          );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      period = ProductionCostPeriod(from: selected.start, to: selected.end);
      data = widget.service.load(period: period);
    });
  }

  bool exporting = false;

  Future<void> export() async {
    if (exporting || !widget.service.canView) {
      return;
    }
    setState(() => exporting = true);
    try {
      await ProductionCostReport(widget.service).exportReport(
        period: period,
        save: (workbook) => (widget.saveReport ?? saveExcelFile)(
          workbook,
          'BaoCaoChiPhiV2-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.xlsx',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('finance.exported'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('finance.exportFailed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String money(int amount, String currency) =>
        '${FinanceAmountFormatter.group(amount.toString())} $currency';
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.costs')),
        actions: [
          if (widget.service.canView)
            IconButton(
              key: const Key('costs-export'),
              icon: const Icon(Icons.file_download),
              tooltip: l10n.text('finance.exportV2'),
              onPressed: exporting ? null : export,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.text('common.retry'),
            onPressed: () {
              setState(() {
                data = widget.service.load(period: period);
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('costs-period'),
                  icon: const Icon(Icons.date_range),
                  onPressed: exporting ? null : selectPeriod,
                  label: Text(
                    period.isAllDates
                        ? l10n.text('costs.allDates')
                        : '${period.from!.toIso8601String().substring(0, 10)} – ${period.to!.toIso8601String().substring(0, 10)}',
                  ),
                ),
                if (!period.isAllDates)
                  TextButton(
                    key: const Key('costs-clear-period'),
                    onPressed: exporting
                        ? null
                        : () {
                            setState(() {
                              period = const ProductionCostPeriod();
                              data = widget.service.load(period: period);
                            });
                          },
                    child: Text(l10n.text('costs.clearPeriod')),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<ProductionCostSnapshot>(
              future: data,
              builder: (context, snapshot) {
                if (!widget.service.canView || snapshot.hasError) {
                  return Center(child: Text(l10n.text('costs.loadFailed')));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final report = snapshot.data!;
                if (report.groups.isEmpty) {
                  return Center(child: Text(l10n.text('costs.empty')));
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(l10n.text('costs.basis')),
                    for (final total in report.totals.entries)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '${l10n.text('costs.total')}: ${money(total.value, total.key)}',
                            key: Key('costs-total-${total.key}'),
                          ),
                        ),
                      ),
                    for (final group in report.groups)
                      Card(
                        child: ExpansionTile(
                          key: Key(
                            'costs-group-${group.parcelId ?? 'general'}-${group.currency}',
                          ),
                          title: Text(
                            group.parcelId == null
                                ? l10n.text('costs.general')
                                : report.parcelLabels[group.parcelId] ??
                                      l10n.text('finance.linkedParcel'),
                          ),
                          subtitle: Text(
                            '${money(group.amountMinor, group.currency)} · '
                            '${l10n.text('costs.documents')}: ${group.documents.length}',
                          ),
                          children: [
                            for (final document in group.documents)
                              ListTile(
                                title: Text(
                                  '${document.code} · ${document.category}',
                                ),
                                subtitle: Text(
                                  '${document.occurredAt.toIso8601String().substring(0, 10)}\n'
                                  '${money(document.amountMinor, document.currency)}',
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
