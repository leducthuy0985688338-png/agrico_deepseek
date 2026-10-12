import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../application/production_cost_summary.dart';
import 'finance_amount_formatter.dart';

class ProductionCostsScreen extends StatefulWidget {
  const ProductionCostsScreen({super.key, required this.service});
  final ProductionCostSummary service;
  @override
  State<ProductionCostsScreen> createState() => _ProductionCostsScreenState();
}

class _ProductionCostsScreenState extends State<ProductionCostsScreen> {
  late Future<ProductionCostSnapshot> data = widget.service.load();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String money(int amount, String currency) =>
        '${FinanceAmountFormatter.group(amount.toString())} $currency';
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.costs')),
        actions: [
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
