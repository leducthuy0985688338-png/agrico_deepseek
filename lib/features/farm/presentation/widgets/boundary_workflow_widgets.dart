import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../data/interchange/kml_interchange.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../controllers/land_parcel_controller.dart';

/// Selects one imported polygon without persisting it.
/// The caller receives a preview only after explicit selection and confirmation.
class KmlBoundaryPicker extends StatefulWidget {
  const KmlBoundaryPicker({super.key, required this.previews});

  final List<LandParcelImportPreview> previews;

  @override
  State<KmlBoundaryPicker> createState() => _KmlBoundaryPickerState();
}

class _KmlBoundaryPickerState extends State<KmlBoundaryPicker> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = selected == null ? null : widget.previews[selected!];
    return AlertDialog(
      title: Text(l10n.text('import.preview.title')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < widget.previews.length; index++)
                ListTile(
                  key: Key('create-import-preview-$index'),
                  selected: selected == index,
                  title: Text(widget.previews[index].name ?? '#${index + 1}'),
                  subtitle: Text(
                    '${widget.previews[index].areaM2.toStringAsFixed(1)} m²',
                  ),
                  onTap: () => setState(() => selected = index),
                ),
              if (preview != null) ...[
                const Divider(),
                Text(
                  '${preview.areaM2.toStringAsFixed(1)} m² · '
                  '${preview.areaHa.toStringAsFixed(3)} ha',
                ),
                Text('${preview.perimeterM.toStringAsFixed(1)} m'),
                Text(
                  '${preview.centroid.latitude.toStringAsFixed(6)}, '
                  '${preview.centroid.longitude.toStringAsFixed(6)}',
                ),
                for (final warning in preview.warnings)
                  Text(l10n.text('import.warning.${warning.name}')),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.text('common.cancel')),
        ),
        FilledButton(
          key: const Key('confirm-create-import-preview'),
          onPressed: preview == null ? null : () => Navigator.pop(context, preview),
          child: Text(l10n.text('common.confirm')),
        ),
      ],
    );
  }
}

class GpsBoundaryPreview extends StatefulWidget {
  const GpsBoundaryPreview({
    super.key,
    required this.controller,
    required this.parcel,
    required this.completedVertices,
  });
  final LandParcelController controller;
  final LandParcel parcel;
  final List<Wgs84Vertex> completedVertices;

  @override
  State<GpsBoundaryPreview> createState() => _GpsBoundaryPreviewState();
}

class _GpsBoundaryPreviewState extends State<GpsBoundaryPreview> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Wgs84PolygonMetrics? metrics;
    try {
      metrics = const Wgs84GeometryService().measure(
        Wgs84Polygon.fromVertices(widget.completedVertices),
      );
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.text('gps.preview.title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (metrics == null)
          Text(l10n.text('landParcel.geometry.invalid'))
        else ...[
          Text(
            '${metrics.areaM2.toStringAsFixed(1)} m² · ${(metrics.areaM2 / 10000).toStringAsFixed(3)} ha',
          ),
          Text('${metrics.perimeterM.toStringAsFixed(1)} m'),
        ],
        FilledButton(
          key: const Key('apply-gps-boundary'),
          onPressed: metrics == null || _isSaving
              ? null
              : () => _confirmAndApply(context),
          child: Text(l10n.text('gps.confirm')),
        ),
      ],
    );
  }

  Future<void> _confirmAndApply(BuildContext context) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    var confirmed = false;
    if (widget.parcel.verificationStatus ==
        BoundaryVerificationStatus.verified) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                AppLocalizations.of(context).text('verification.confirm.title'),
              ),
              content: Text(
                AppLocalizations.of(
                  context,
                ).text('landParcel.boundary.verifiedConfirmation'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    AppLocalizations.of(context).text('common.cancel'),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    AppLocalizations.of(context).text('common.confirm'),
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }
    }
    try {
      await widget.controller.applyGps(
        parcelId: widget.parcel.id,
        vertices: widget.completedVertices,
        confirmVerifiedReplacement: confirmed,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class KmlImportPreviewView extends StatefulWidget {
  const KmlImportPreviewView({
    super.key,
    required this.controller,
    required this.parcel,
    required this.preview,
  });

  final LandParcelController controller;
  final LandParcel parcel;
  final LandParcelImportPreview preview;

  @override
  State<KmlImportPreviewView> createState() => _KmlImportPreviewViewState();
}

class _KmlImportPreviewViewState extends State<KmlImportPreviewView> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preview = widget.preview;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.text('import.preview.title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (preview.name != null) Text(preview.name!),
        Text(
          '${preview.areaM2.toStringAsFixed(1)} m² · ${preview.areaHa.toStringAsFixed(3)} ha',
        ),
        Text('${preview.perimeterM.toStringAsFixed(1)} m'),
        Text(
          '${preview.centroid.latitude.toStringAsFixed(6)}, ${preview.centroid.longitude.toStringAsFixed(6)}',
        ),
        ...preview.metadata.values.entries.map(
          (entry) => Text('${entry.key}: ${entry.value}'),
        ),
        ...preview.warnings.map(
          (warning) => Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text(l10n.text('import.warning.${warning.name}')),
            ),
          ),
        ),
        FilledButton(
          key: const Key('confirm-kml-import'),
          onPressed: _isSaving ? null : _confirm,
          child: Text(l10n.text('common.confirm')),
        ),
      ],
    );
  }

  Future<void> _confirm() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    var verifiedConfirmation = false;

    if (widget.parcel.verificationStatus ==
        BoundaryVerificationStatus.verified) {
      verifiedConfirmation =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              content: Text(
                AppLocalizations.of(
                  dialogContext,
                ).text('landParcel.boundary.verifiedConfirmation'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    AppLocalizations.of(dialogContext).text('common.cancel'),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                    AppLocalizations.of(dialogContext).text('common.confirm'),
                  ),
                ),
              ],
            ),
          ) ??
          false;

      if (!verifiedConfirmation || !mounted) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }
    }

    try {
      final result = await widget.controller.confirmImport(
        parcelId: widget.parcel.id,
        preview: widget.preview,
        confirmVerifiedReplacement: verifiedConfirmation,
      );

      if (!mounted || !result.isSuccess) return;

      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
