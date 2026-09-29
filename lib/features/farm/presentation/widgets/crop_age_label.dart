import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/land_survey.dart';

/// Age is a recorded snapshot; it does not automatically advance with time.
String? cropAgeLabel(AppLocalizations l10n, CropRecord crop) {
  final months = crop.ageMonths;
  if (months == null) return null;
  return '${l10n.text('crop.age')}: '
      '${months ~/ 12} ${l10n.text('crop.age.years')} '
      '${months % 12} ${l10n.text('crop.age.months')}';
}

String cropAgeSuffix(AppLocalizations l10n, CropRecord crop) {
  final label = cropAgeLabel(l10n, crop);
  return label == null ? '' : ' · $label';
}
