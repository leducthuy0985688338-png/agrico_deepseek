import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/permissions/authorization.dart';
import '../../application/land_parcel_application_service.dart';
import '../../domain/entities/land_survey.dart';
import '../controllers/land_parcel_controller.dart';
import 'boundary_history_screen.dart';

class LandParcelDetailScreen extends StatefulWidget {
  const LandParcelDetailScreen({
    super.key,
    required this.controller,
    required this.parcelId,
    this.onGpsRequested,
    this.onImportRequested,
  });
  final LandParcelController controller;
  final String parcelId;
  final VoidCallback? onGpsRequested;
  final VoidCallback? onImportRequested;

  @override
  State<LandParcelDetailScreen> createState() => _LandParcelDetailScreenState();
}

class _LandParcelDetailScreenState extends State<LandParcelDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.loadDetail(widget.parcelId);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    if (controller.phase == ParcelPresentationPhase.loading ||
        controller.detail?.parcel.id != widget.parcelId) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (controller.phase == ParcelPresentationPhase.persistenceError ||
        controller.phase == ParcelPresentationPhase.permissionDenied) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            l10n.text(controller.messageKey ?? 'parcel.detail.error'),
          ),
        ),
      );
    }
    final data = controller.detail!;
    final parcel = data.parcel;
    final household = data.household;
    return Scaffold(
      appBar: AppBar(title: Text('${parcel.parcelCode} · ${parcel.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${parcel.areaHa.toStringAsFixed(2)} ha · ${l10n.text('verification.${parcel.verificationStatus.name}')}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (data.village.isNotEmpty || data.owner.isNotEmpty)
            Text('${data.village} · ${data.owner}'),
          _section(context, l10n.text('parcel.section.overview'), [
            _row(
              l10n.text('geometry.areaM2'),
              '${parcel.areaM2.toStringAsFixed(1)} m²',
            ),
            _row(
              l10n.text('geometry.areaHa'),
              '${parcel.areaHa.toStringAsFixed(3)} ha',
            ),
            _row(
              l10n.text('geometry.perimeter'),
              '${parcel.perimeterM.toStringAsFixed(1)} m',
            ),
            _row(
              l10n.text('geometry.centroid'),
              '${parcel.centroid.latitude.toStringAsFixed(6)}, ${parcel.centroid.longitude.toStringAsFixed(6)}',
            ),
            _row(
              l10n.text('boundary.source'),
              l10n.text('boundary.source.${parcel.boundarySource.name}'),
            ),
            if (parcel.horizontalAccuracyM != null)
              _row(
                l10n.text('geometry.accuracy'),
                '±${parcel.horizontalAccuracyM} m',
              ),
            if (parcel.boundaryConfidence != null)
              _row(
                l10n.text('geometry.confidence'),
                '${(parcel.boundaryConfidence! * 100).toStringAsFixed(0)}%',
              ),
          ]),
          if (household != null) ...[
            _section(context, l10n.text('survey.administrativeLocation'), [
              Text(
                [
                  household.administrativeLocation.countryName,
                  household.administrativeLocation.provinceName,
                  household.administrativeLocation.districtName,
                  household.administrativeLocation.villageName,
                ].join(' · '),
              ),
            ]),
            _section(context, l10n.text('survey.household'), [
              _row(l10n.text('household.code'), household.householdCode),
              _row(l10n.text('household.head'), household.headOfHouseholdName),
              if (household.phone != null)
                _row(l10n.text('household.phone'), household.phone!),
              if (household.alternativeContact != null)
                _row(
                  l10n.text('household.alternativeContact'),
                  household.alternativeContact!,
                ),
            ]),
          ],
          if (data.landUse != null) _landUse(context, l10n, data.landUse!),
          _section(
            context,
            l10n.text('survey.crop'),
            data.crops.isEmpty
                ? [Text(l10n.text('crop.empty'))]
                : data.crops
                      .map(
                        (crop) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(crop.cropType),
                          subtitle: Text(
                            '${crop.quantity} ${crop.unit} · ${l10n.text('crop.condition.${crop.condition.name}')}',
                          ),
                        ),
                      )
                      .toList(),
          ),
          _section(
            context,
            l10n.text('survey.record'),
            data.surveys.isEmpty
                ? [Text(l10n.text('survey.empty'))]
                : data.surveys
                      .map(
                        (survey) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(survey.surveyDate.toLocal().toString()),
                          subtitle: Text(
                            '${survey.surveyorMembershipId} · v${survey.boundaryVersion}${survey.notes == null ? '' : '\n${survey.notes}'}',
                          ),
                        ),
                      )
                      .toList(),
          ),
          _section(
            context,
            l10n.text('survey.attachment'),
            data.attachments.isEmpty
                ? [Text(l10n.text('attachment.empty'))]
                : data.attachments
                      .map(
                        (attachment) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _attachmentIcon(attachment.attachmentType),
                          ),
                          title: Text(attachment.fileName),
                          subtitle: Text(attachment.mimeType),
                        ),
                      )
                      .toList(),
          ),
          _section(context, l10n.text('googleEarth.title'), [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (controller.can(
                  PermissionCodes.fieldMeasure,
                  parcelId: parcel.id,
                ))
                  OutlinedButton.icon(
                    onPressed: widget.onGpsRequested,
                    icon: const Icon(Icons.gps_fixed),
                    label: Text(l10n.text('gps.start')),
                  ),
                if (controller.can(
                  PermissionCodes.fieldGoogleEarthImport,
                  parcelId: parcel.id,
                ))
                  OutlinedButton.icon(
                    onPressed: widget.onImportRequested,
                    icon: const Icon(Icons.upload_file),
                    label: Text(l10n.text('googleEarth.import')),
                  ),
                if (controller.can(
                  PermissionCodes.fieldGoogleEarthExport,
                  parcelId: parcel.id,
                )) ...[
                  OutlinedButton(
                    onPressed: () => controller.exportAndOpen(
                      parcel.id,
                      LandParcelInterchangeFormat.kml,
                    ),
                    child: Text(l10n.text('googleEarth.exportKml')),
                  ),
                  OutlinedButton(
                    onPressed: () => controller.exportAndOpen(
                      parcel.id,
                      LandParcelInterchangeFormat.kmz,
                    ),
                    child: Text(l10n.text('googleEarth.exportKmz')),
                  ),
                  if (controller.fileOpener != null)
                    OutlinedButton.icon(
                      onPressed: () => controller.openInGoogleEarth(parcel.id),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.text('googleEarth.open')),
                    ),
                ],
              ],
            ),
          ]),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    BoundaryHistoryScreen(history: parcel.boundaryHistory),
              ),
            ),
            icon: const Icon(Icons.history),
            label: Text(l10n.text('boundary.history.title')),
          ),
        ],
      ),
    );
  }

  Widget _landUse(
    BuildContext context,
    AppLocalizations l10n,
    LandUseProfile value,
  ) => _section(context, l10n.text('survey.landUse'), [
    _row(
      l10n.text('survey.landUse'),
      l10n.text('landUse.${value.landUseType.name}'),
    ),
    _row(
      l10n.text('survey.landCondition'),
      l10n.text('landCondition.${value.currentCondition.name}'),
    ),
    _row(
      l10n.text('survey.clearingStatus'),
      l10n.text('clearing.${value.clearingStatus.name}'),
    ),
    _row(
      l10n.text('survey.readinessStatus'),
      l10n.text('readiness.${value.readinessStatus.name}'),
    ),
  ]);
  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              ...children,
            ],
          ),
        ),
      );
  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
  IconData _attachmentIcon(ParcelAttachmentType type) => switch (type) {
    ParcelAttachmentType.photo => Icons.photo,
    ParcelAttachmentType.document => Icons.description,
    ParcelAttachmentType.other => Icons.attach_file,
  };
}
