import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/land_survey.dart';

class CropEditorDialog extends StatefulWidget {
  const CropEditorDialog({
    super.key,
    required this.original,
    required this.parcelId,
  });

  final CropRecord? original;
  final String parcelId;

  @override
  State<CropEditorDialog> createState() => _CropEditorDialogState();
}

class _CropEditorDialogState extends State<CropEditorDialog> {
  CropGrowthStage? growthStage;
  late CropCondition condition;
  String? error;

  @override
  void initState() {
    super.initState();
    growthStage = widget.original?.growthStage;
    condition = widget.original?.condition ?? CropCondition.unknown;
  }

  late final type = TextEditingController(text: widget.original?.cropType);
  late final quantity = TextEditingController(
    text: widget.original?.quantity.toString(),
  );
  late final variety = TextEditingController(text: widget.original?.variety);
  late final notes = TextEditingController(text: widget.original?.notes);
  late final year = TextEditingController(
    text: widget.original?.plantingYear?.toString(),
  );
  late final date = TextEditingController(
    text: widget.original?.plantingDate == null
        ? ''
        : '${widget.original!.plantingDate!.year.toString().padLeft(4, '0')}-${widget.original!.plantingDate!.month.toString().padLeft(2, '0')}-${widget.original!.plantingDate!.day.toString().padLeft(2, '0')}',
  );
  late final unit = TextEditingController(text: widget.original?.unit);
  late final ageYears = TextEditingController(
    text: widget.original?.ageMonths == null
        ? ''
        : '${widget.original!.ageMonths! ~/ 12}',
  );
  late final ageRemainder = TextEditingController(
    text: widget.original?.ageMonths == null
        ? ''
        : '${widget.original!.ageMonths! % 12}',
  );

  @override
  void dispose() {
    type.dispose();
    quantity.dispose();
    unit.dispose();
    variety.dispose();
    notes.dispose();
    year.dispose();
    date.dispose();
    ageYears.dispose();
    ageRemainder.dispose();
    super.dispose();
  }

  void _save() {
    final yearsText = ageYears.text.trim();
    final monthsText = ageRemainder.text.trim();
    final years = yearsText.isEmpty ? 0 : int.tryParse(yearsText);
    final months = monthsText.isEmpty ? 0 : int.tryParse(monthsText);
    if (years == null ||
        months == null ||
        years < 0 ||
        months < 0 ||
        months > 11) {
      setState(() => error = 'crop.age.invalid');
      return;
    }
    DateTime? plantingDate;
    final rawDate = date.text.trim();
    if (rawDate.isNotEmpty) {
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(rawDate);
      if (match == null) {
        setState(() => error = 'crop.date.invalid');
        return;
      }
      final y = int.parse(match[1]!);
      final m = int.parse(match[2]!);
      final d = int.parse(match[3]!);
      plantingDate = DateTime.utc(y, m, d);
      if (y < 1 ||
          plantingDate.year != y ||
          plantingDate.month != m ||
          plantingDate.day != d) {
        setState(() => error = 'crop.date.invalid');
        return;
      }
    }
    final plantingYear = year.text.trim().isEmpty
        ? plantingDate?.year
        : int.tryParse(year.text.trim());
    if (year.text.trim().isNotEmpty && plantingYear == null) {
      setState(() => error = 'crop.validation.failed');
      return;
    }
    final original = widget.original;
    final now = DateTime.now().toUtc();
    final value = CropRecord(
      id: original?.id ?? 'draft-${now.microsecondsSinceEpoch}',
      parcelId: widget.parcelId,
      cropType: type.text.trim(),
      quantity:
          double.tryParse(quantity.text.trim().replaceAll(',', '.')) ??
          double.nan,
      unit: unit.text.trim(),
      variety: variety.text.trim().isEmpty ? null : variety.text.trim(),
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      plantingDate: plantingDate,
      plantingYear: plantingYear,
      ageMonths: yearsText.isEmpty && monthsText.isEmpty
          ? null
          : years * 12 + months,
      growthStage: growthStage,
      condition: condition,
      active: true,
      createdAt: original?.createdAt ?? now,
      createdBy: original?.createdBy ?? 'draft',
      updatedAt: now,
      updatedBy: 'draft',
    );
    try {
      value.validate();
    } on FormatException {
      setState(() => error = 'crop.validation.failed');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        l10n.text(widget.original == null ? 'crop.add' : 'crop.edit'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('crop-type'),
              controller: type,
              decoration: InputDecoration(labelText: l10n.text('crop.type')),
            ),
            TextField(
              key: const Key('crop-quantity'),
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.text('crop.quantity'),
              ),
            ),
            TextField(
              key: const Key('crop-unit'),
              controller: unit,
              decoration: InputDecoration(labelText: l10n.text('crop.unit')),
            ),
            TextField(
              key: const Key('crop-variety'),
              controller: variety,
              decoration: InputDecoration(labelText: l10n.text('crop.variety')),
            ),
            TextField(
              key: const Key('crop-planting-date'),
              controller: date,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: l10n.text('crop.plantingDate'),
                hintText: 'YYYY-MM-DD',
              ),
            ),
            TextField(
              key: const Key('crop-planting-year'),
              controller: year,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.text('crop.plantingYear'),
              ),
            ),
            DropdownButtonFormField<CropCondition>(
              key: const Key('crop-condition'),
              initialValue: condition,
              decoration: InputDecoration(
                labelText: l10n.text('crop.condition'),
              ),
              items: [
                for (final value in CropCondition.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(l10n.text('crop.condition.${value.name}')),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => condition = value);
                }
              },
            ),
            TextField(
              key: const Key('crop-notes'),
              controller: notes,
              maxLines: 2,
              decoration: InputDecoration(labelText: l10n.text('crop.notes')),
            ),
            if (error != null)
              Text(
                l10n.text(error!),
                key: const Key('crop-editor-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextField(
              key: const Key('crop-age-years'),
              controller: ageYears,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.text('crop.age.yearsInput'),
              ),
            ),
            TextField(
              key: const Key('crop-age-months'),
              controller: ageRemainder,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.text('crop.age.monthsInput'),
              ),
            ),
            DropdownButtonFormField<CropGrowthStage?>(
              key: const Key('crop-growth-stage'),
              initialValue: growthStage,
              decoration: InputDecoration(
                labelText: l10n.text('crop.growthStage'),
              ),
              items: [
                DropdownMenuItem<CropGrowthStage?>(
                  value: null,
                  child: Text(l10n.text('crop.growthStage.unknown')),
                ),
                for (final stage in CropGrowthStage.values)
                  DropdownMenuItem<CropGrowthStage?>(
                    value: stage,
                    child: Text(l10n.text('crop.growthStage.${stage.name}')),
                  ),
              ],
              onChanged: (value) => setState(() => growthStage = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.text('common.cancel')),
        ),
        FilledButton(
          key: const Key('save-crop'),
          onPressed: _save,
          child: Text(l10n.text('common.save')),
        ),
      ],
    );
  }
}
