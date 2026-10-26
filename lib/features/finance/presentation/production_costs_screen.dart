import 'dart:math';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../services/report_file_saver.dart';
import '../application/production_cost_parcel_filter.dart';
import '../application/production_cost_period.dart';
import '../application/production_cost_report.dart';
import '../application/production_cost_summary.dart';
import 'finance_amount_formatter.dart';
import 'finance_document_details_dialog.dart';

class ProductionCostsScreen extends StatefulWidget {
  const ProductionCostsScreen({
    super.key,
    required this.service,
    this.saveReport,
    this.pickPeriod,
    this.initialParcelId,
  });
  final ProductionCostSummary service;
  final String? initialParcelId;
  final Future<DateTimeRange?> Function(BuildContext, DateTimeRange?)?
  pickPeriod;
  final Future<void> Function(Excel workbook, String fileName)? saveReport;
  @override
  State<ProductionCostsScreen> createState() => _ProductionCostsScreenState();
}

class _ProductionCostsScreenState extends State<ProductionCostsScreen> {
  final search = TextEditingController();
  late String selectedParcel = widget.initialParcelId == null
      ? 'all'
      : 'parcel:${widget.initialParcelId}';
  String selectedCurrency = 'all';
  ProductionCostPeriod period = const ProductionCostPeriod();
  bool exporting = false;
  bool refreshing = false;
  int filterRevision = 0;

  String? get currencyFilter =>
      selectedCurrency == 'all' ? null : selectedCurrency.substring(9);
  ProductionCostParcelFilter get parcelFilter => selectedParcel == 'all'
      ? const ProductionCostParcelFilter.all()
      : selectedParcel == 'general'
      ? const ProductionCostParcelFilter.general()
      : ProductionCostParcelFilter.parcel(selectedParcel.substring(7));
  bool get hasFilters =>
      search.text.isNotEmpty ||
      selectedParcel != 'all' ||
      selectedCurrency != 'all' ||
      !period.isAllDates;
  bool allowChange() {
    if (!mounted || exporting) {
      return false;
    }
    if (!widget.service.canView) {
      setState(() {});
      return false;
    }
    return true;
  }

  late Future<ProductionCostSnapshot> data = load();

  Future<ProductionCostSnapshot> load() => widget.service.load(
    period: period,
    parcelFilter: parcelFilter,
    currency: currencyFilter,
    query: search.text,
  );

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void changeFilters(VoidCallback change) {
    if (!allowChange()) {
      return;
    }
    setState(() {
      change();
      filterRevision++;
      data = load();
    });
  }

  void clearFilters() {
    if (!allowChange() || !hasFilters) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    changeFilters(() {
      search.clear();
      selectedParcel = 'all';
      selectedCurrency = 'all';
      period = const ProductionCostPeriod();
    });
  }

  Future<void> refresh() async {
    if (!mounted || refreshing || exporting) {
      return;
    }
    if (!widget.service.canView) {
      setState(() {});
      return;
    }
    final refreshed = load();
    setState(() {
      refreshing = true;
      data = refreshed;
    });
    try {
      await refreshed;
    } catch (_) {
      /* The scrollable error state permits retry. */
    } finally {
      if (mounted) {
        setState(() {
          refreshing = false;
        });
      }
    }
  }

  Future<void> selectPeriod() async {
    if (!allowChange()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final revision = filterRevision;
    final initial = period.isAllDates
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
    if (!mounted) {
      return;
    }
    if (!widget.service.canView) {
      setState(() {});
      return;
    }
    if (!allowChange() || selected == null || revision != filterRevision) {
      return;
    }
    changeFilters(() {
      period = ProductionCostPeriod(from: selected.start, to: selected.end);
    });
  }

  Future<void> export(bool filtered) async {
    if (!allowChange()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final exportPeriod = filtered ? period : const ProductionCostPeriod();
    final exportParcel = filtered
        ? parcelFilter
        : const ProductionCostParcelFilter.all();
    final exportCurrency = filtered ? currencyFilter : null;
    final exportQuery = filtered ? search.text : '';
    setState(() {
      exporting = true;
    });
    try {
      await ProductionCostReport(widget.service).exportReport(
        period: exportPeriod,
        parcelFilter: exportParcel,
        currency: exportCurrency,
        query: exportQuery,
        save: (book) => (widget.saveReport ?? saveExcelFile)(
          book,
          'BaoCaoChiPhiV2-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.xlsx',
        ),
      );
      if (mounted) {
        message('finance.exported');
      }
    } catch (_) {
      if (mounted) {
        message('finance.exportFailed');
      }
    } finally {
      if (mounted) {
        setState(() {
          exporting = false;
        });
      }
    }
  }

  void message(String key) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.text(key))));
  String money(int amount, String currency) =>
      '${FinanceAmountFormatter.group(amount.toString())} $currency';
  String date(DateTime value) => value.toIso8601String().substring(0, 10);
  Widget option(String text) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  List<Widget> filters(ProductionCostSnapshot? report) {
    final l10n = context.l10n;
    final ids = <String>{
      ...(report?.availableParcelIds ?? <String>{}),
      ?parcelFilter.parcelId,
    }.toList()..sort();
    final currencies = <String>{
      'LAK',
      'VND',
      ...(report?.availableCurrencies ?? <String>{}),
      ?currencyFilter,
    }.toList()..sort();
    return [
      TextField(
        key: const Key('costs-search'),
        controller: search,
        enabled: !exporting,
        decoration: InputDecoration(
          hintText: l10n.text('finance.search'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: search.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('costs-clear-search'),
                  icon: const Icon(Icons.clear),
                  tooltip: l10n.text('finance.clearSearch'),
                  onPressed: exporting
                      ? null
                      : () => changeFilters(search.clear),
                ),
        ),
        onChanged: (_) => changeFilters(() {}),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final parcel = DropdownButtonFormField<String>(
            key: const Key('costs-parcel'),
            initialValue: selectedParcel,
            isExpanded: true,
            decoration: InputDecoration(
              label: option(l10n.text('task.parcel')),
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: option(l10n.text('costs.allParcels')),
              ),
              DropdownMenuItem(
                value: 'general',
                child: option(l10n.text('costs.general')),
              ),
              for (final id in ids)
                DropdownMenuItem(
                  value: 'parcel:$id',
                  child: option(
                    report?.parcelLabels[id] ??
                        '${l10n.text('finance.linkedParcel')} ($id)',
                  ),
                ),
            ],
            onChanged: exporting
                ? null
                : (value) {
                    if (value != null) {
                      changeFilters(() {
                        selectedParcel = value;
                      });
                    }
                  },
          );
          final currency = DropdownButtonFormField<String>(
            key: const Key('costs-currency'),
            initialValue: selectedCurrency,
            isExpanded: true,
            decoration: InputDecoration(
              label: option(l10n.text('finance.currency')),
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: option(l10n.text('common.all')),
              ),
              for (final code in currencies)
                DropdownMenuItem(value: 'currency:$code', child: option(code)),
            ],
            onChanged: exporting
                ? null
                : (value) {
                    if (value != null) {
                      changeFilters(() {
                        selectedCurrency = value;
                      });
                    }
                  },
          );
          // Stack selectors when text scaling would leave their labels too narrow.
          if (constraints.maxWidth < 360 &&
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
              children: [parcel, const SizedBox(height: 12), currency],
            );
          }
          return Row(
            children: [
              Expanded(flex: 2, child: parcel),
              const SizedBox(width: 8),
              Expanded(child: currency),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      Wrap(
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
                  : '${date(period.from!)} – ${date(period.to!)}',
            ),
          ),
          if (!period.isAllDates)
            TextButton(
              key: const Key('costs-clear-period'),
              onPressed: exporting
                  ? null
                  : () => changeFilters(() {
                      period = const ProductionCostPeriod();
                    }),
              child: Text(l10n.text('costs.clearPeriod')),
            ),
        ],
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> results(ProductionCostSnapshot report) {
    final l10n = context.l10n;
    return [
      Text(l10n.text('costs.basis')),
      Text(
        '${l10n.text('finance.documentCount')}: ${report.documentCount}',
        key: const Key('costs-document-count'),
      ),
      if (hasFilters)
        Text(
          l10n.text('costs.filteredScope'),
          key: const Key('costs-filtered-scope'),
        ),
      if (report.groups.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.text(hasFilters ? 'finance.noSearchResults' : 'costs.empty'),
          ),
        ),
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
                        '${l10n.text('finance.linkedParcel')} (${group.parcelId})',
            ),
            subtitle: Text(
              '${money(group.amountMinor, group.currency)} · ${l10n.text('costs.documents')}: ${group.documents.length}',
            ),
            children: [
              for (final document in group.documents)
                ListTile(
                  key: Key('costs-document-${document.id}'),
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    showFinanceDocumentDetails(
                      context: context,
                      service: widget.service.finance,
                      id: document.id,
                      canView: () => widget.service.canView,
                    );
                  },
                  title: Text('${document.code} · ${document.category}'),
                  subtitle: Text(
                    '${date(document.occurredAt)}\n${money(document.amountMinor, document.currency)}',
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.costs')),
        actions: [
          if (widget.service.canView && hasFilters)
            IconButton(
              key: const Key('costs-clear-filters'),
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: l10n.text('finance.clearFilters'),
              onPressed: exporting ? null : clearFilters,
            ),
          if (widget.service.canExport)
            PopupMenuButton<bool>(
              key: const Key('costs-export'),
              icon: const Icon(Icons.file_download),
              tooltip: l10n.text('finance.exportV2'),
              enabled: !exporting,
              onSelected: export,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: true,
                  key: const Key('costs-export-filtered'),
                  child: Text(l10n.text('finance.exportFiltered')),
                ),
                PopupMenuItem(
                  value: false,
                  key: const Key('costs-export-all'),
                  child: Text(l10n.text('finance.exportAll')),
                ),
              ],
            ),
          IconButton(
            key: const Key('costs-refresh-button'),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.text('common.retry'),
            onPressed: refreshing || exporting ? null : refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        key: const Key('costs-refresh'),
        onRefresh: refresh,
        child: FutureBuilder<ProductionCostSnapshot>(
          future: data,
          builder: (context, snapshot) {
            final allowed = widget.service.canView;
            final waiting = snapshot.connectionState != ConnectionState.done;
            return ListView(
              key: const Key('costs-scroll'),
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (allowed) ...filters(snapshot.data),
                if (!allowed || snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.text('costs.loadFailed')),
                  )
                else if (waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasData)
                  ...results(snapshot.data!),
              ],
            );
          },
        ),
      ),
    );
  }
}
