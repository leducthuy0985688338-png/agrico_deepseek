import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/identity/domain/business_reference_code.dart';
import '../../../core/localization/app_localizations.dart';
import '../data/local/sqlite_finance_document_repository.dart';
import '../domain/finance_document.dart';

class FinanceDocumentsScreen extends StatefulWidget {
  const FinanceDocumentsScreen({
    super.key,
    required this.repository,
    required this.organizationId,
  });

  final SqliteFinanceDocumentRepository repository;
  final String organizationId;

  @override
  State<FinanceDocumentsScreen> createState() => _FinanceDocumentsScreenState();
}

class _FinanceDocumentsScreenState extends State<FinanceDocumentsScreen> {
  late Future<List<FinanceDocument>> documents = _load();

  Future<List<FinanceDocument>> _load() =>
      widget.repository.listByOrganization(widget.organizationId);

  Future<void> _add() async {
    final saved = await showDialog<FinanceDocument>(
      context: context,
      builder: (_) => _FinanceDocumentDialog(
        repository: widget.repository,
        organizationId: widget.organizationId,
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => documents = _load());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved.code)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('module.finance')),
        actions: [IconButton(
          key: const Key('finance-add'),
          tooltip: l10n.text('finance.add'),
          icon: const Icon(Icons.add),
          onPressed: _add,
        )],
      ),
      body: FutureBuilder<List<FinanceDocument>>(
        future: documents,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.text('finance.saveFailed')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return Center(child: Text(l10n.text('common.empty')));
          }
          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final document = snapshot.data![index];
              return ListTile(
                title: Text('${document.code} · ${document.category}'),
                subtitle: Text('${document.occurredAt.year}-'
                    '${document.occurredAt.month.toString().padLeft(2, '0')}-'
                    '${document.occurredAt.day.toString().padLeft(2, '0')}'),
                trailing: Text('${document.amountMinor} ${document.currency}'),
              );
            },
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
  });

  final SqliteFinanceDocumentRepository repository;
  final String organizationId;

  @override
  State<_FinanceDocumentDialog> createState() => _FinanceDocumentDialogState();
}

class _FinanceDocumentDialogState extends State<_FinanceDocumentDialog> {
  final category = TextEditingController();
  final amount = TextEditingController();
  BusinessDocumentKind kind = BusinessDocumentKind.payment;
  String currency = 'LAK';
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
    final parsedAmount = int.tryParse(amount.text);
    if (category.text.trim().isEmpty || parsedAmount == null || parsedAmount <= 0) {
      setState(() => error = AppLocalizations.of(context).text('finance.invalid'));
      return;
    }
    setState(() { saving = true; error = null; });
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
      );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) setState(() => error = AppLocalizations.of(context).text('finance.saveFailed'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.text('finance.add')),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<BusinessDocumentKind>(
            initialValue: kind,
            items: [BusinessDocumentKind.receipt, BusinessDocumentKind.payment]
                .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(l10n.text(value == BusinessDocumentKind.receipt
                      ? 'finance.receipt' : 'finance.payment')),
                )).toList(),
            onChanged: saving ? null : (value) => setState(() => kind = value!),
          ),
          TextField(
            key: const Key('finance-category'),
            controller: category,
            decoration: InputDecoration(labelText: l10n.text('finance.category')),
          ),
          TextField(
            key: const Key('finance-amount'),
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: l10n.text('finance.amount')),
          ),
          DropdownButtonFormField<String>(
            initialValue: currency,
            decoration: InputDecoration(labelText: l10n.text('finance.currency')),
            items: const [DropdownMenuItem(value: 'LAK', child: Text('LAK')),
                DropdownMenuItem(value: 'VND', child: Text('VND'))],
            onChanged: saving ? null : (value) => setState(() => currency = value!),
          ),
          TextButton(
            onPressed: saving ? null : () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (mounted && selected != null) setState(() => date = selected);
            },
            child: Text('${l10n.text('finance.date')}: ${date.year}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}'),
          ),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      )),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.text('common.cancel'))),
        FilledButton(
          key: const Key('finance-save'),
          onPressed: saving ? null : _save,
          child: Text(l10n.text('common.save')),
        ),
      ],
    );
  }
}
