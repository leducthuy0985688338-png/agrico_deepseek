import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../widgets/crop_age_label.dart';

class LandParcelBoundaryDraft {
  LandParcelBoundaryDraft({required this.boundary, required this.source})
    : metrics = const Wgs84GeometryService().measure(boundary);

  final Wgs84Polygon boundary;
  final BoundarySource source;
  final Wgs84PolygonMetrics metrics;
}

class _CropEditorDialog extends StatefulWidget {
  const _CropEditorDialog({required this.original, required this.parcelId});

  final CropRecord? original;
  final String parcelId;

  @override
  State<_CropEditorDialog> createState() => _CropEditorDialogState();
}

class _CropEditorDialogState extends State<_CropEditorDialog> {
  late final type = TextEditingController(text: widget.original?.cropType);
  late final quantity = TextEditingController(
    text: widget.original?.quantity.toString(),
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
    ageYears.dispose();
    ageRemainder.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final yearsText = ageYears.text.trim();
    final monthsText = ageRemainder.text.trim();
    final years = yearsText.isEmpty ? 0 : int.tryParse(yearsText);
    final months = monthsText.isEmpty ? 0 : int.tryParse(monthsText);
    if (years == null || months == null || months > 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.text('crop.age.invalid'))),
      );
      return;
    }
    final original = widget.original;
    final now = DateTime.now().toUtc();
    Navigator.of(context).pop(CropRecord(
      id: original?.id ?? 'draft-${now.microsecondsSinceEpoch}',
      parcelId: widget.parcelId,
      cropType: type.text.trim(),
      quantity: double.tryParse(quantity.text) ?? 0,
      unit: unit.text.trim(),
      ageMonths: yearsText.isEmpty && monthsText.isEmpty
          ? null
          : years * 12 + months,
      variety: original?.variety,
      plantingYear: original?.plantingYear,
      plantingDate: original?.plantingDate,
      notes: original?.notes,
      condition: original?.condition ?? CropCondition.unknown,
      active: true,
      createdAt: original?.createdAt ?? now,
      createdBy: original?.createdBy ?? 'draft',
      updatedAt: now,
      updatedBy: 'draft',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.text(widget.original == null ? 'crop.add' : 'crop.edit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: type,
              decoration: InputDecoration(labelText: l10n.text('crop.type')),
            ),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.text('crop.quantity')),
            ),
            TextField(
              controller: unit,
              decoration: InputDecoration(labelText: l10n.text('crop.unit')),
            ),
            TextField(
              key: const Key('crop-age-years'),
              controller: ageYears,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l10n.text('crop.age.yearsInput')),
            ),
            TextField(
              key: const Key('crop-age-months'),
              controller: ageRemainder,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l10n.text('crop.age.monthsInput')),
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

class LandParcelFormValue {
  const LandParcelFormValue({
    required this.parcelCode,
    required this.name,
    required this.active,
    required this.country,
    required this.province,
    required this.district,
    required this.village,
    required this.householdCode,
    required this.ownerName,
    required this.phone,
    required this.alternativeContact,
    required this.crops,
    this.boundaryDraft,
  });
  final String parcelCode;
  final String name;
  final bool active;
  final String country;
  final String province;
  final String district;
  final String village;
  final String householdCode;
  final String ownerName;
  final String phone;
  final String alternativeContact;
  final List<CropRecord> crops;
  final LandParcelBoundaryDraft? boundaryDraft;
}

class LandParcelFormScreen extends StatefulWidget {
  const LandParcelFormScreen({
    super.key,
    this.parcel,
    this.household,
    this.crops = const [],
    this.landUse,
    this.surveys = const [],
    this.attachments = const [],
    this.onAddAttachment,
    this.boundaryDraft,
    this.onGpsRequested,
    this.onImportRequested,
    required this.onSubmit,
  });
  final LandParcel? parcel;
  final Household? household;
  final List<CropRecord> crops;
  final LandUseProfile? landUse;
  final List<LandParcelSurvey> surveys;
  final List<ParcelAttachment> attachments;
  final VoidCallback? onAddAttachment;
  final LandParcelBoundaryDraft? boundaryDraft;
  final Future<LandParcelBoundaryDraft?> Function()? onGpsRequested;
  final Future<LandParcelBoundaryDraft?> Function()? onImportRequested;
  final Future<void> Function(LandParcelFormValue value) onSubmit;

  @override
  State<LandParcelFormScreen> createState() => _LandParcelFormScreenState();
}

class _LandParcelFormScreenState extends State<LandParcelFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late List<CropRecord> crops;
  bool saving = false;
  late bool active;
  late LandUseType landUseType;
  late LandCondition landCondition;
  late ClearingStatus clearingStatus;
  late ReadinessStatus readinessStatus;
  LandParcelBoundaryDraft? boundaryDraft;

  @override
  void initState() {
    super.initState();
    final location = widget.household?.administrativeLocation;
    fields = {
      'code': TextEditingController(text: widget.parcel?.parcelCode),
      'name': TextEditingController(text: widget.parcel?.name),
      'country': TextEditingController(text: location?.countryName),
      'province': TextEditingController(text: location?.provinceName),
      'district': TextEditingController(text: location?.districtName),
      'village': TextEditingController(text: location?.villageName),
      'householdCode': TextEditingController(
        text: widget.household?.householdCode,
      ),
      'owner': TextEditingController(
        text: widget.household?.headOfHouseholdName,
      ),
      'phone': TextEditingController(text: widget.household?.phone),
      'contact': TextEditingController(
        text: widget.household?.alternativeContact,
      ),
    };
    crops = [...widget.crops];
    active = widget.parcel?.active ?? true;
    landUseType = widget.landUse?.landUseType ?? LandUseType.agricultural;
    landCondition = widget.landUse?.currentCondition ?? LandCondition.unknown;
    clearingStatus = widget.landUse?.clearingStatus ?? ClearingStatus.unknown;
    readinessStatus =
        widget.landUse?.readinessStatus ?? ReadinessStatus.unknown;
    boundaryDraft = boundaryDraft;
  }

  @override
  void dispose() {
    for (final value in fields.values) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parcel = widget.parcel;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.text(
            parcel == null ? 'parcel.create.title' : 'parcel.edit.title',
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(context, l10n.text('parcel.section.identity'), [
              _required('code', l10n.text('parcel.code')),
              _required('name', l10n.text('parcel.name')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.text('common.active')),
                value: active,
                onChanged: (value) => setState(() => active = value),
              ),
            ]),
            _section(context, l10n.text('survey.administrativeLocation'), [
              _field('country', l10n.text('location.country')),
              _field('province', l10n.text('location.province')),
              _field('district', l10n.text('location.district')),
              _field('village', l10n.text('location.village')),
            ]),
            _section(context, l10n.text('survey.household'), [
              _field('householdCode', l10n.text('household.code')),
              _field('owner', l10n.text('household.head')),
              _field(
                'phone',
                l10n.text('household.phone'),
                keyboard: TextInputType.phone,
              ),
              _field('contact', l10n.text('household.alternativeContact')),
            ]),
            _section(context, l10n.text('parcel.section.boundary'), [
              if (parcel == null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('create-boundary-gps'),
                      onPressed: widget.onGpsRequested == null
                          ? null
                          : _requestGps,
                      icon: const Icon(Icons.gps_fixed),
                      label: Text(l10n.text('gps.start')),
                    ),
                    OutlinedButton.icon(
                      key: const Key('create-boundary-import'),
                      onPressed: widget.onImportRequested == null
                          ? null
                          : _requestImport,
                      icon: const Icon(Icons.file_open),
                      label: const Text('KML/KMZ'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (boundaryDraft != null)
                _readOnly(
                  l10n.text('boundary.source'),
                  l10n.text('boundary.source.${boundaryDraft!.source.name}'),
                  'boundary-source-readonly',
                ),
              _readOnly(
                l10n.text('geometry.areaM2'),
                boundaryDraft != null
                    ? '${boundaryDraft!.metrics.areaM2.toStringAsFixed(1)} m²'
                    : parcel == null
                    ? '—'
                    : '${parcel.areaM2.toStringAsFixed(1)} m²',
                'area-readonly',
              ),
              _readOnly(
                l10n.text('geometry.areaHa'),
                boundaryDraft != null
                    ? '${boundaryDraft!.metrics.areaHa.toStringAsFixed(3)} ha'
                    : parcel == null
                    ? '—'
                    : '${parcel.areaHa.toStringAsFixed(3)} ha',
                'area-ha-readonly',
              ),
              _readOnly(
                l10n.text('geometry.perimeter'),
                boundaryDraft != null
                    ? '${boundaryDraft!.metrics.perimeterM.toStringAsFixed(1)} m'
                    : parcel == null
                    ? '—'
                    : '${parcel.perimeterM.toStringAsFixed(1)} m',
                'perimeter-readonly',
              ),
              if (parcel != null)
                _readOnly(
                  l10n.text('boundary.version'),
                  '${parcel.boundaryVersion}',
                  'boundary-version-readonly',
                ),
            ]),
            _section(context, l10n.text('survey.landUse'), [
              _enumField<LandUseType>(
                landUseType,
                LandUseType.values,
                'landUse',
                (value) => setState(() => landUseType = value),
              ),
              _enumField<LandCondition>(
                landCondition,
                LandCondition.values,
                'landCondition',
                (value) => setState(() => landCondition = value),
              ),
              _enumField<ClearingStatus>(
                clearingStatus,
                ClearingStatus.values,
                'clearing',
                (value) => setState(() => clearingStatus = value),
                labelKey: 'survey.clearingStatus',
              ),
              _enumField<ReadinessStatus>(
                readinessStatus,
                ReadinessStatus.values,
                'readiness',
                (value) => setState(() => readinessStatus = value),
                labelKey: 'survey.readinessStatus',
              ),
            ]),
            _section(context, l10n.text('survey.crop'), [
              ...crops.asMap().entries.map(
                (entry) => ListTile(
                  key: Key('crop-${entry.value.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value.cropType),
                  subtitle: Text(
                    '${entry.value.quantity} ${entry.value.unit}'
                    '${cropAgeSuffix(l10n, entry.value)}',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: l10n.text('common.edit'),
                        onPressed: () => _editCrop(entry.key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.text('common.remove'),
                        onPressed: () =>
                            setState(() => crops.removeAt(entry.key)),
                      ),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('add-crop'),
                onPressed: () => _editCrop(null),
                icon: const Icon(Icons.add),
                label: Text(l10n.text('crop.add')),
              ),
            ]),
            _section(
              context,
              l10n.text('survey.record'),
              widget.surveys.isEmpty
                  ? [Text(l10n.text('survey.empty'))]
                  : widget.surveys
                        .map(
                          (value) => Text(
                            '${value.surveyDate.toLocal()} · v${value.boundaryVersion} · ${value.surveyorMembershipId}',
                          ),
                        )
                        .toList(),
            ),
            _section(context, l10n.text('survey.attachment'), [
              ...widget.attachments.map(
                (value) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(value.fileName),
                  subtitle: Text(value.mimeType),
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.onAddAttachment,
                icon: const Icon(Icons.add),
                label: Text(l10n.text('attachment.addMetadata')),
              ),
            ]),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('save-parcel'),
              onPressed: saving ? null : _save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(),
                    )
                  : Text(l10n.text('common.save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );
  Widget _field(String key, String label, {TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: fields[key],
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
    ),
  );
  Widget _required(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: fields[key],
      decoration: InputDecoration(labelText: label),
      validator: (value) => value == null || value.trim().isEmpty
          ? AppLocalizations.of(context).text('validation.required')
          : null,
    ),
  );
  Widget _readOnly(String label, String value, String key) => ListTile(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(value),
  );

  Widget _enumField<T extends Enum>(
    T value,
    List<T> values,
    String prefix,
    ValueChanged<T> changed, {
    String? labelKey,
  }) => DropdownButtonFormField<T>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: AppLocalizations.of(
        context,
      ).text(labelKey ?? 'survey.$prefix'),
    ),
    items: values
        .map(
          (item) => DropdownMenuItem(
            value: item,
            child: Text(
              AppLocalizations.of(context).text('$prefix.${item.name}'),
            ),
          ),
        )
        .toList(),
    onChanged: (next) {
      if (next != null) changed(next);
    },
  );

  Future<void> _requestGps() async {
    final draft = await widget.onGpsRequested?.call();
    if (!mounted || draft == null) return;
    setState(() => boundaryDraft = draft);
  }

  Future<void> _requestImport() async {
    final draft = await widget.onImportRequested?.call();
    if (!mounted || draft == null) return;
    setState(() => boundaryDraft = draft);
  }

  Future<void> _editCrop(int? index) async {
    final original = index == null ? null : crops[index];
    final value = await showDialog<CropRecord>(
      context: context,
      builder: (_) => _CropEditorDialog(
        original: original,
        parcelId: widget.parcel?.id ?? 'draft',
      ),
    );
    if (value != null && mounted) {
      setState(() {
        if (index == null) {
          crops.add(value);
        } else {
          crops[index] = value;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.onSubmit(
        LandParcelFormValue(
          parcelCode: fields['code']!.text.trim(),
          name: fields['name']!.text.trim(),
          active: active,
          country: fields['country']!.text.trim(),
          province: fields['province']!.text.trim(),
          district: fields['district']!.text.trim(),
          village: fields['village']!.text.trim(),
          householdCode: fields['householdCode']!.text.trim(),
          ownerName: fields['owner']!.text.trim(),
          phone: fields['phone']!.text.trim(),
          alternativeContact: fields['contact']!.text.trim(),
          crops: List.unmodifiable(crops),
          boundaryDraft: boundaryDraft,
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
