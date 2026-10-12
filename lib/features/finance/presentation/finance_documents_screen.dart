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

class FinanceDocumentsScreen extends StatefulWidget {
  const FinanceDocumentsScreen({
    super.key,
    required this.service,
    this.saveReport,
  });

  final FinanceDocumentService service;
  final Future<void> Function(Excel workbook, String fileName)? saveReport;

  @override
  State<FinanceDocumentsScreen> createState() => _FinanceDocumentsScreenState();
}

class _FinanceDocumentsScreenState extends State<FinanceDocumentsScreen> {
  bool exporting = false;
  Map<String, String> parcelLabels = {};
  late Future<(List<FinanceDocument>, List<FinanceCurrencyTotal>)> data =
      _load();

  Future<(List<FinanceDocument>, List<FinanceCurrencyTotal>)> _load() async {
    final documents = await widget.service.listByOrganization(
      widget.service.organizationId,
    );
    final totals = await FinanceDocumentSummary(
      widget.service,
    ).byOrganization(widget.service.organizationId);
    final parcels = await widget.service.availableParcels();
    parcelLabels = {
      for (final parcel in parcels)
        parcel.id: '${parcel.parcelCode} · ${parcel.name}',
    };
    return (documents, totals);
  }

  Future<void> _showDetails(String id) async {
    try {
      final (document, parcelLabel) = await widget.service.details(id);
      if (!mounted || !widget.service.canView) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final l10n = AppLocalizations.of(dialogContext);
          final allowed = widget.service.canView;
          return AlertDialog(
            title: Text(l10n.text('finance.details')),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: allowed
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            '${l10n.text('finance.code')}: ${document.code}',
                          ),
                          SelectableText(
                            '${l10n.text('finance.kind')}: ${l10n.text(document.kind == BusinessDocumentKind.receipt ? 'finance.receipt' : 'finance.payment')}',
                          ),
                          SelectableText(
                            '${l10n.text('finance.date')}: ${document.occurredAt.toIso8601String().substring(0, 10)}',
                          ),
                          SelectableText(
                            '${l10n.text('finance.amount')}: ${FinanceAmountFormatter.group(document.amountMinor.toString())} ${document.currency}',
                          ),
                          SelectableText(
                            '${l10n.text('finance.category')}: ${document.category}',
                          ),
                          SelectableText(
                            '${l10n.text('task.parcel')}: ${document.parcelId == null ? l10n.text('finance.noParcel') : parcelLabel ?? l10n.text('finance.linkedParcel')}',
                          ),
                          SelectableText(
                            '${l10n.text('work.notes')}: ${document.description?.trim().isNotEmpty == true ? document.description! : '—'}',
                          ),
                        ],
                      )
                    : Text(l10n.text('finance.loadDetailsFailed')),
              ),
            ),
            actions: [
              TextButton(
                key: const Key('finance-details-close'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.text('finance.close')),
              ),
            ],
          );
        },
      );
    } catch (_) {
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

  Future<void> _add() async {
    if (!widget.service.canCreate) {
      return;
    }
    List<LandParcel> parcels;
    try {
      parcels = await widget.service.availableParcels();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).text('finance.saveFailed'),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(saved.code)));
  }

  Future<void> _export() async {
    setState(() => exporting = true);
    try {
      await widget.service.exportReport(
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
          if (widget.service.canExport)
            IconButton(
              key: const Key('finance-export-v2'),
              tooltip: l10n.text('finance.exportV2'),
              icon: const Icon(Icons.file_download),
              onPressed: exporting ? null : _export,
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
      body: FutureBuilder<(List<FinanceDocument>, List<FinanceCurrencyTotal>)>(
        future: data,
        builder: (context, snapshot) {
          if (!widget.service.canView || snapshot.hasError) {
            return Center(child: Text(l10n.text('finance.saveFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (documents, totals) = snapshot.data!;
          if (documents.isEmpty) {
            return Center(child: Text(l10n.text('common.empty')));
          }
          return ListView(
            children: [
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
                          '${l10n.text('finance.receipt')}: ${FinanceAmountFormatter.group(total.receiptsMinor.toString())}',
                        ),
                        Text(
                          '${l10n.text('finance.payment')}: ${FinanceAmountFormatter.group(total.paymentsMinor.toString())}',
                        ),
                        Text(
                          '${l10n.text('finance.balance')}: ${FinanceAmountFormatter.group(total.balanceMinor.toString())}',
                        ),
                      ],
                    ),
                  ),
                ),
              for (final document in documents)
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
                      title: Text('${document.code} · ${document.category}'),
                      subtitle: Text(
                        '${document.occurredAt.year}-'
                        '${document.occurredAt.month.toString().padLeft(2, '0')}-'
                        '${document.occurredAt.day.toString().padLeft(2, '0')}'
                        '${document.parcelId == null ? '' : '\n${l10n.text('task.parcel')}: ${parcelLabels[document.parcelId] ?? l10n.text('finance.linkedParcel')}'}',
                      ),
                      trailing: Text(
                        '${FinanceAmountFormatter.group(document.amountMinor.toString())} $unit',
                      ),
                    );
                  },
                ),
            ],
          );
        },
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

  final FinanceDocumentStore repository;
  final String organizationId;
  final List<LandParcel> parcels;

  @override
  State<_FinanceDocumentDialog> createState() => _FinanceDocumentDialogState();
}

class _FinanceDocumentDialogState extends State<_FinanceDocumentDialog> {
  final category = TextEditingController();
  final amount = TextEditingController();
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
      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      final id = 'finance-$now-${Random.secure().nextInt(1 << 32)}';
      final saved = await widget.repository.create(
        id: id,
        organizationId: widget.organizationId,
        kind: kind,
        occurredAt: date,
        amountMinor: parsedAmount,
        currency: currency,
        category: category.text.trim(),
        parcelId: parcelId,
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted)
        setState(
          () => error = AppLocalizations.of(context).text('finance.saveFailed'),
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
