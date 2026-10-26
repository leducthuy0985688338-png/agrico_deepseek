import 'package:flutter/material.dart';
import '../../../core/identity/domain/business_reference_code.dart';
import '../../../core/localization/app_localizations.dart';
import '../application/finance_document_service.dart';
import 'finance_amount_formatter.dart';

Future<void> showFinanceDocumentDetails({
  required BuildContext context,
  required FinanceDocumentService service,
  required String id,
  bool Function()? canView,
}) async {
  bool allowed() => service.canView && (canView?.call() ?? true);
  if (!context.mounted || !allowed()) {
    return;
  }
  try {
    final (document, parcelLabel) = await service.details(id);
    if (!context.mounted || !allowed()) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        final permitted = allowed();
        return AlertDialog(
          title: Text(l10n.text('finance.details')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: permitted
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
                          '${l10n.text('finance.amount')}: ${FinanceAmountFormatter.groupExact(document.amountText)} ${document.currency}',
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
    if (context.mounted) {
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
