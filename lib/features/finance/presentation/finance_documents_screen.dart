import '../application/finance_document_filter.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:excel/excel.dart';

import '../../../core/identity/domain/business_reference_code.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../services/report_file_saver.dart';
import '../application/finance_document_summary.dart';
import '../application/finance_document_service.dart';
import '../domain/finance_document.dart';
import '../../farm/domain/entities/land_parcel.dart';
import 'finance_amount_formatter.dart';
import 'finance_document_details_dialog.dart';

class FinanceDocumentsScreen extends StatefulWidget {
  const FinanceDocumentsScreen({
    super.key,
    required this.service,
    this.saveReport,
    this.pickPeriod,
    this.initialParcelId,
  });

  final FinanceDocumentService service;
  final String? initialParcelId;
  final Future<DateTimeRange?> Function(BuildContext, DateTimeRange?)?
  pickPeriod;
  final Future<void> Function(Excel workbook, String fileName)? saveReport;

  @override
  State<FinanceDocumentsScreen> createState() => _FinanceDocumentsScreenState();
}

class _FinanceDocumentsScreenState extends State<FinanceDocumentsScreen> {
  bool exporting = false;
  bool refreshing = false;
  final search = TextEditingController();
  BusinessDocumentKind? kindFilter;
  DateTimeRange? period;
  late String selectedParcel = widget.initialParcelId == null
      ? 'all'
      : 'parcel:${widget.initialParcelId}';
  String selectedCurrency = 'all';

  static String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  FinanceDocumentFilter get currentFilter => FinanceDocumentFilter(
    query: search.text,
    kind: kindFilter,
    from: period?.start,
    to: period?.end,
    parcel: selectedParcel,
    currency: selectedCurrency == 'all' ? null : selectedCurrency.substring(9),
  );

  Future<void> _selectPeriod() async {
    if (!widget.service.canView) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = widget.pickPeriod != null
        ? await widget.pickPeriod!(context, period)
        : await showDateRangePicker(
            context: context,
            firstDate: DateTime(1900),
            lastDate: DateTime(2100, 12, 31),
            initialDateRange: period,
          );
    if (!mounted) {
      return;
    }
    if (!widget.service.canView) {
      setState(() {});
      return;
    }
    if (selected == null) {
      return;
    }
    setState(() => period = selected);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Map<String, String> parcelLabels = {};
  late Future<(List<FinanceDocument>, List<FinanceCurrencyTotal>)> data =
      _load();

  Future<(List<FinanceDocument>, List<FinanceCurrencyTotal>)> _load() async {
    final documents = await widget.service.listByOrganization(
      widget.service.organizationId,
    );
    final totals = FinanceDocumentSummary.fromDocuments(
      documents,
      widget.service.organizationId,
    );
    final parcels = await widget.service.availableParcels();
    parcelLabels = {
      for (final parcel in parcels)
        parcel.id: '${parcel.parcelCode} · ${parcel.name}',
    };
    return (documents, totals);
  }

  Future<void> _showDetails(String id) => showFinanceDocumentDetails(
    context: context,
    service: widget.service,
    id: id,
  );

  Future<void> _add() async {
    if (!widget.service.canCreate) {
      return;
    }
    List<LandParcel> parcels;
    try {
      parcels = await widget.service.availableParcels();
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).failure(failure, 'finance.saveFailed'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted || !widget.service.canCreate) {
      return;
    }
    final saved = await showDialog<FinanceDocument>(
      context: context,
      builder: (_) => _FinanceDocumentDialog(
        repository: widget.service,
        organizationId: widget.service.organizationId,
        parcels: parcels,
      ),
    );
    if (!mounted || saved == null) return;
    setState(() {
      data = _load();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.code.isEmpty
              ? switch (AppLocalizations.of(context).locale.languageCode) {
                  'vi' => 'Đã lưu chờ duyệt; chưa ghi sổ tiền',
                  'lo' => 'ບັນທຶກລໍຖ້າອະນຸມັດ; ຍັງບໍ່ລົງບັນຊີ',
                  _ => 'Pending approval saved; cash ledger unchanged',
                }
              : saved.code,
        ),
      ),
    );
  }

  bool get hasFilters =>
      search.text.isNotEmpty ||
      kindFilter != null ||
      period != null ||
      selectedParcel != 'all' ||
      selectedCurrency != 'all';

  void _clearFilters() {
    if (!widget.service.canView) {
      setState(() {});
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      search.clear();
      kindFilter = null;
      period = null;
      selectedParcel = 'all';
      selectedCurrency = 'all';
    });
  }

  Future<void> _refresh() async {
    if (!mounted || refreshing) {
      return;
    }
    if (!widget.service.canView) {
      setState(() {});
      return;
    }
    refreshing = true;
    final refreshed = _load();
    setState(() {
      data = refreshed;
    });
    try {
      await refreshed;
    } catch (failure) {
      // FutureBuilder displays the failure; the scrollable error permits retry.
    } finally {
      refreshing = false;
    }
  }

  Future<void> _showFilteredTotals() async {
    if (!widget.service.canView) {
      return;
    }
    final filter = currentFilter;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final documents = await widget.service.listByOrganization(
        widget.service.organizationId,
      );
      if (!mounted || !widget.service.canView) {
        return;
      }
      final visible = documents.where(filter.matches).toList();
      final totals = FinanceDocumentSummary.fromDocuments(
        visible,
        widget.service.organizationId,
      );
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final l10n = AppLocalizations.of(dialogContext);
          return AlertDialog(
            key: const Key('finance-filtered-totals-dialog'),
            title: Text(l10n.text('finance.filteredTotals')),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: widget.service.canView
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l10n.text('finance.documentCount')}: ${visible.length}',
                            key: const Key('finance-filtered-count'),
                          ),
                          for (final total in totals)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                key: Key(
                                  'finance-filtered-total-${total.currency}',
                                ),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(total.currency),
                                  Text(
                                    '${l10n.text('finance.receipt')}: ${FinanceAmountFormatter.groupExact(total.receiptsText)}',
                                  ),
                                  Text(
                                    '${l10n.text('finance.payment')}: ${FinanceAmountFormatter.groupExact(total.paymentsText)}',
                                  ),
                                  Text(
                                    '${l10n.text('finance.balance')}: ${FinanceAmountFormatter.groupExact(total.balanceText)}',
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : Text(l10n.text('finance.loadDetailsFailed')),
              ),
            ),
            actions: [
              TextButton(
                key: const Key('finance-filtered-totals-close'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.text('finance.close')),
              ),
            ],
          );
        },
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('finance.loadDetailsFailed'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _export(bool filtered) async {
    if (exporting || !widget.service.canExport) {
      return;
    }
    final filter = filtered ? currentFilter : const FinanceDocumentFilter();
    setState(() => exporting = true);
    try {
      await widget.service.exportReport(
        filter: filter,
        save: (workbook) => (widget.saveReport ?? saveExcelFile)(
          workbook,
          'BaoCaoChungTuV2-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.xlsx',
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
    } catch (failure) {
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
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.finance')),
        actions: [
          if (widget.service.canView && hasFilters)
            IconButton(
              key: const Key('finance-clear-filters'),
              tooltip: l10n.text('finance.clearFilters'),
              icon: const Icon(Icons.filter_alt_off),
              onPressed: _clearFilters,
            ),
          if (widget.service.canView)
            IconButton(
              key: const Key('finance-filtered-totals'),
              tooltip: l10n.text('finance.filteredTotals'),
              icon: const Icon(Icons.summarize_outlined),
              onPressed: _showFilteredTotals,
            ),
          if (widget.service.canExport)
            PopupMenuButton<bool>(
              key: const Key('finance-export-v2'),
              tooltip: l10n.text('finance.exportV2'),
              icon: const Icon(Icons.file_download),
              enabled: !exporting,
              onSelected: _export,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: false,
                  key: const Key('finance-export-all'),
                  child: Text(l10n.text('finance.exportAll')),
                ),
                PopupMenuItem(
                  value: true,
                  key: const Key('finance-export-filtered'),
                  child: Text(l10n.text('finance.exportFiltered')),
                ),
              ],
            ),
          if (widget.service.canCreate)
            IconButton(
              key: const Key('finance-add'),
              tooltip: l10n.text('finance.add'),
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.service.canView)
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const Key('finance-search'),
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.text('finance.search'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('finance-search-clear'),
                          tooltip: l10n.text('finance.clearSearch'),
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(search.clear),
                        ),
                ),
              ),
            ),
          if (widget.service.canView)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    key: const Key('finance-kind-all'),
                    label: Text(l10n.text('common.all')),
                    selected: kindFilter == null,
                    onSelected: (_) => setState(() => kindFilter = null),
                  ),
                  ChoiceChip(
                    key: const Key('finance-kind-receipt'),
                    label: Text(l10n.text('finance.receipt')),
                    selected: kindFilter == BusinessDocumentKind.receipt,
                    onSelected: (_) => setState(
                      () => kindFilter = BusinessDocumentKind.receipt,
                    ),
                  ),
                  ChoiceChip(
                    key: const Key('finance-kind-payment'),
                    label: Text(l10n.text('finance.payment')),
                    selected: kindFilter == BusinessDocumentKind.payment,
                    onSelected: (_) => setState(
                      () => kindFilter = BusinessDocumentKind.payment,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.service.canView)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('finance-period'),
                      onPressed: _selectPeriod,
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        period == null
                            ? l10n.text('finance.allDates')
                            : '${_dateLabel(period!.start)} – ${_dateLabel(period!.end)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (period != null)
                    IconButton(
                      key: const Key('finance-clear-period'),
                      tooltip: l10n.text('finance.clearPeriod'),
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => period = null),
                    ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              key: const Key('finance-refresh'),
              onRefresh: _refresh,
              child: FutureBuilder<(List<FinanceDocument>, List<FinanceCurrencyTotal>)>(
                future: data,
                builder: (context, snapshot) {
                  if (!widget.service.canView || snapshot.hasError) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l10n.text('finance.saveFailed')),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final (documents, totals) = snapshot.data!;
                  final query = search.text.trim().toLowerCase();
                  final parcelIds = <String>{
                    ...parcelLabels.keys,
                    for (final document in documents) ?document.parcelId,
                    if (selectedParcel.startsWith('parcel:'))
                      selectedParcel.substring(7),
                  }.toList()..sort();
                  final currencies = <String>{
                    'LAK',
                    'VND',
                    for (final document in documents) document.currency,
                    if (selectedCurrency != 'all')
                      selectedCurrency.substring(9),
                  }.toList()..sort();
                  final visible = documents
                      .where(currentFilter.matches)
                      .toList();
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                key: const Key('finance-parcel-filter'),
                                initialValue: selectedParcel,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: l10n.text('task.parcel'),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text(
                                      l10n.text('common.all'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'general',
                                    child: Text(
                                      l10n.text('finance.noParcel'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  for (final id in parcelIds)
                                    DropdownMenuItem(
                                      value: 'parcel:$id',
                                      child: Text(
                                        parcelLabels[id] ??
                                            '${l10n.text('finance.linkedParcel')} ($id)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null && widget.service.canView) {
                                    setState(() => selectedParcel = value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: const Key('finance-currency-filter'),
                                initialValue: selectedCurrency,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  label: Text(
                                    l10n.text('finance.currency'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text(
                                      l10n.text('common.all'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  for (final currency in currencies)
                                    DropdownMenuItem(
                                      value: 'currency:$currency',
                                      child: Text(
                                        currency,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null && widget.service.canView) {
                                    setState(() => selectedCurrency = value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (query.isNotEmpty ||
                          kindFilter != null ||
                          period != null ||
                          selectedParcel != 'all' ||
                          selectedCurrency != 'all')
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(l10n.text('finance.searchScope')),
                        ),
                      for (final total in totals)
                        Card(
                          key: Key('finance-total-${total.currency}'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${l10n.text('finance.summary')} · ${total.currency}',
                                ),
                                Text(
                                  '${l10n.text('finance.receipt')}: ${FinanceAmountFormatter.groupExact(total.receiptsText)}',
                                ),
                                Text(
                                  '${l10n.text('finance.payment')}: ${FinanceAmountFormatter.groupExact(total.paymentsText)}',
                                ),
                                Text(
                                  '${l10n.text('finance.balance')}: ${FinanceAmountFormatter.groupExact(total.balanceText)}',
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l10n.text(
                              documents.isEmpty
                                  ? 'common.empty'
                                  : 'finance.noSearchResults',
                            ),
                          ),
                        ),
                      for (final document in visible)
                        Builder(
                          builder: (context) {
                            final unit = switch (document.currency) {
                              'LAK' => l10n.text('finance.currency.lak.short'),
                              'VND' => l10n.text('finance.currency.vnd.short'),
                              _ => document.currency,
                            };
                            return ListTile(
                              key: Key('finance-document-${document.id}'),
                              onTap: () => _showDetails(document.id),
                              title: Text(
                                '${document.code} · ${document.category}',
                              ),
                              subtitle: Text(
                                '${document.occurredAt.year}-'
                                '${document.occurredAt.month.toString().padLeft(2, '0')}-'
                                '${document.occurredAt.day.toString().padLeft(2, '0')}'
                                '${document.parcelId == null ? '' : '\n${l10n.text('task.parcel')}: ${parcelLabels[document.parcelId] ?? l10n.text('finance.linkedParcel')}'}',
                              ),
                              trailing: Text(
                                '${FinanceAmountFormatter.groupExact(document.amountText)} $unit',
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceDocumentDialog extends StatefulWidget {
  const _FinanceDocumentDialog({
    required this.repository,
    required this.organizationId,
    required this.parcels,
  });

  final FinanceDocumentService repository;
  final String organizationId;
  final List<LandParcel> parcels;

  @override
  State<_FinanceDocumentDialog> createState() => _FinanceDocumentDialogState();
}

class _FinanceDocumentDialogState extends State<_FinanceDocumentDialog> {
  late final String requestId =
      'finance-${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  final category = TextEditingController();
  final amount = TextEditingController();
  final beneficiaryParty = TextEditingController();
  BusinessDocumentKind kind = BusinessDocumentKind.payment;
  String currency = 'LAK';
  String? parcelId;
  DateTime date = DateTime.now();
  bool saving = false;
  String? error;

  @override
  void dispose() {
    category.dispose();
    amount.dispose();
    beneficiaryParty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsedAmount = int.tryParse(
      FinanceAmountFormatter.digits(amount.text),
    );
    if (category.text.trim().isEmpty ||
        parsedAmount == null ||
        parsedAmount <= 0) {
      setState(
        () => error = AppLocalizations.of(context).text('finance.invalid'),
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = requestId;
      final saved = await widget.repository.create(
        id: id,
        organizationId: widget.organizationId,
        kind: kind,
        occurredAt: date,
        amountMinor: parsedAmount,
        currency: currency,
        category: category.text.trim(),
        beneficiaryPartyId: beneficiaryParty.text.trim().isEmpty
            ? null
            : beneficiaryParty.text.trim(),
        parcelId: parcelId,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (failure) {
      if (mounted)
        setState(
          () => error = AppLocalizations.of(
            context,
          ).failure(failure, 'finance.saveFailed'),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.text('finance.add')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('finance-beneficiary-party'),
              controller: beneficiaryParty,
              decoration: InputDecoration(
                labelText: switch (l10n.locale.languageCode) {
                  'vi' => 'ID đối tác/người hưởng (cần liên kết được xác minh)',
                  'lo' => 'ID ຄູ່ຄ້າ/ຜູ້ຮັບ (ຕ້ອງຢືນຢັນການເຊື່ອມ)',
                  _ => 'Party/beneficiary ID (verified binding required)',
                },
              ),
            ),
            DropdownButtonFormField<BusinessDocumentKind>(
              isExpanded: true,
              initialValue: kind,
              items:
                  [BusinessDocumentKind.receipt, BusinessDocumentKind.payment]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            l10n.text(
                              value == BusinessDocumentKind.receipt
                                  ? 'finance.receipt'
                                  : 'finance.payment',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => kind = value!),
            ),
            DropdownButtonFormField<String>(
              key: const Key('finance-parcel'),
              isExpanded: true,
              initialValue: parcelId,
              decoration: InputDecoration(labelText: l10n.text('task.parcel')),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    l10n.text('finance.noParcel'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final parcel in widget.parcels)
                  DropdownMenuItem(
                    value: parcel.id,
                    child: Text(
                      '${parcel.parcelCode} · ${parcel.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => parcelId = value),
            ),
            TextField(
              key: const Key('finance-category'),
              controller: category,
              decoration: InputDecoration(
                labelText: l10n.text('finance.category'),
              ),
            ),
            TextField(
              key: const Key('finance-amount'),
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FinanceAmountFormatter()],
              decoration: InputDecoration(
                labelText: l10n.text('finance.amount'),
              ),
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: currency,
              decoration: InputDecoration(
                labelText: l10n.text('finance.currency'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'LAK',
                  child: Text(
                    l10n.text('finance.currency.lak'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'VND',
                  child: Text(
                    l10n.text('finance.currency.vnd'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => currency = value!),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (mounted && selected != null)
                        setState(() => date = selected);
                    },
              child: Text(
                '${l10n.text('finance.date')}: ${date.year}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.text('common.cancel')),
        ),
        FilledButton(
          key: const Key('finance-save'),
          onPressed: saving ? null : _save,
          child: Text(l10n.text('common.save')),
        ),
      ],
    );
  }
}
