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
  });
  final ProductionCostSummary service;
  final Future<void> Function(Excel workbook, String fileName)? saveReport;
  @override
  State<ProductionCostsScreen> createState() => _ProductionCostsScreenState();
}

class _ProductionCostsScreenState extends State<ProductionCostsScreen> {
  late Future<ProductionCostSnapshot> data = widget.service.load();
  bool exporting = false;

  Future<void> export() async {
    if (exporting || !widget.service.canView) {
      return;
    }
    setState(() => exporting = true);
    try {
      await ProductionCostReport(widget.service).exportReport(
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
                data = widget.service.load();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<ProductionCostSnapshot>(
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
    );
  }
}
