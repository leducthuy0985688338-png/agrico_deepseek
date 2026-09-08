import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';

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
    required this.onSubmit,
  });
  final LandParcel? parcel;
  final Household? household;
  final List<CropRecord> crops;
  final LandUseProfile? landUse;
  final List<LandParcelSurvey> surveys;
  final List<ParcelAttachment> attachments;
  final VoidCallback? onAddAttachment;
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
              _readOnly(
                l10n.text('geometry.areaM2'),
                parcel == null ? '—' : '${parcel.areaM2.toStringAsFixed(1)} m²',
                'area-readonly',
              ),
              _readOnly(
                l10n.text('geometry.areaHa'),
                parcel == null ? '—' : '${parcel.areaHa.toStringAsFixed(3)} ha',
                'area-ha-readonly',
              ),
              _readOnly(
                l10n.text('geometry.perimeter'),
                parcel == null
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
              ),
              _enumField<ReadinessStatus>(
                readinessStatus,
                ReadinessStatus.values,
                'readiness',
                (value) => setState(() => readinessStatus = value),
              ),
            ]),
            _section(context, l10n.text('survey.crop'), [
              ...crops.asMap().entries.map(
                (entry) => ListTile(
                  key: Key('crop-${entry.value.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value.cropType),
                  subtitle: Text('${entry.value.quantity} ${entry.value.unit}'),
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
    ValueChanged<T> changed,
  ) => DropdownButtonFormField<T>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: AppLocalizations.of(context).text('survey.$prefix'),
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

  Future<void> _editCrop(int? index) async {
    final original = index == null ? null : crops[index];
    final type = TextEditingController(text: original?.cropType);
    final quantity = TextEditingController(text: original?.quantity.toString());
    final unit = TextEditingController(text: original?.unit);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.text(index == null ? 'crop.add' : 'crop.edit')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: type,
                  decoration: InputDecoration(
                    labelText: l10n.text('crop.type'),
                  ),
                ),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.text('crop.quantity'),
                  ),
                ),
                TextField(
                  controller: unit,
                  decoration: InputDecoration(
                    labelText: l10n.text('crop.unit'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.text('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.text('common.save')),
            ),
          ],
        );
      },
    );
    if (accepted == true && mounted) {
      final value = CropRecord(
        id: original?.id ?? 'draft-${DateTime.now().microsecondsSinceEpoch}',
        parcelId: widget.parcel?.id ?? 'draft',
        cropType: type.text.trim(),
        quantity: double.tryParse(quantity.text) ?? 0,
        unit: unit.text.trim(),
        condition: original?.condition ?? CropCondition.unknown,
        active: true,
        createdAt: original?.createdAt ?? DateTime.now().toUtc(),
        createdBy: original?.createdBy ?? 'draft',
        updatedAt: DateTime.now().toUtc(),
        updatedBy: 'draft',
      );
      setState(() {
        if (index == null) {
          crops.add(value);
        } else {
          crops[index] = value;
        }
      });
    }
    type.dispose();
    quantity.dispose();
    unit.dispose();
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
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}
