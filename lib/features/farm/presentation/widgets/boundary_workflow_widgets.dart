import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../data/interchange/kml_interchange.dart';
import '../../domain/entities/land_parcel.dart';
import '../../domain/geometry/wgs84_geometry.dart';
import '../controllers/land_parcel_controller.dart';

class GpsBoundaryPreview extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Wgs84PolygonMetrics? metrics;
    try {
      metrics = const Wgs84GeometryService().measure(
        Wgs84Polygon.fromVertices(completedVertices),
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
          onPressed: metrics == null ? null : () => _confirmAndApply(context),
          child: Text(l10n.text('gps.confirm')),
        ),
      ],
    );
  }

  Future<void> _confirmAndApply(BuildContext context) async {
    var confirmed = false;
    if (parcel.verificationStatus == BoundaryVerificationStatus.verified) {
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
      if (!confirmed) return;
    }
    await controller.applyGps(
      parcelId: parcel.id,
      vertices: completedVertices,
      confirmVerifiedReplacement: confirmed,
    );
  }
}

class KmlImportPreviewView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          onPressed: () => _confirm(context),
          child: Text(l10n.text('common.confirm')),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    var verifiedConfirmation = false;
    if (parcel.verificationStatus == BoundaryVerificationStatus.verified) {
      verifiedConfirmation =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
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
      if (!verifiedConfirmation) return;
    }
    await controller.confirmImport(
      parcelId: parcel.id,
      preview: preview,
      confirmVerifiedReplacement: verifiedConfirmation,
    );
  }
}
