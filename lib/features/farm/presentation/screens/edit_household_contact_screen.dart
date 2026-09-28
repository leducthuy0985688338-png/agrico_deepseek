import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/update_household_contact.dart';
import '../../domain/entities/land_survey.dart';

class EditHouseholdContactScreen extends StatefulWidget {
  const EditHouseholdContactScreen({
    super.key,
    required this.household,
    required this.subject,
    required this.update,
  });

  final Household household;
  final AuthorizationSubject subject;
  final UpdateHouseholdContact update;

  @override
  State<EditHouseholdContactScreen> createState() =>
      _EditHouseholdContactScreenState();
}

class _EditHouseholdContactScreenState extends State<EditHouseholdContactScreen> {
  late final TextEditingController head = TextEditingController(
    text: widget.household.headOfHouseholdName,
  );
  late final TextEditingController phone = TextEditingController(
    text: widget.household.phone ?? '',
  );
  late final TextEditingController contact = TextEditingController(
    text: widget.household.alternativeContact ?? '',
  );
  bool saving = false;

  @override
  void dispose() {
    head.dispose();
    phone.dispose();
    contact.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || head.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      final updated = await widget.update.execute(
        subject: widget.subject,
        householdId: widget.household.id,
        headName: head.text,
        phone: phone.text,
        alternativeContact: contact.text,
      );
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).text('household.saveFailed')),
        ));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('household.edit'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.household.householdCode),
        Text(l10n.text('household.editScope')),
        TextField(
          key: const Key('household-edit-head'),
          controller: head,
          decoration: InputDecoration(labelText: l10n.text('household.head')),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const Key('household-edit-phone'),
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: l10n.text('household.phone')),
        ),
        TextField(
          key: const Key('household-edit-contact'),
          controller: contact,
          decoration: InputDecoration(
              labelText: l10n.text('household.alternativeContact')),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('household-edit-save'),
          onPressed: saving || head.text.trim().isEmpty ? null : save,
          child: Text(l10n.text('common.save')),
        ),
        if (saving) const Center(child: CircularProgressIndicator()),
      ]),
    );
  }
}
