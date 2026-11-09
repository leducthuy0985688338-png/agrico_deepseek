/// AGRICO project identity.
///
/// A project has two distinct properties:
/// - [id]: stable identifier used for relationships. Never derived from the
///   human-visible code, never regenerated on app start.
/// - [code]: prefix used for numbering production parcel codes
///   (for example `AGR-NONG-L001`). The code is not an identifier and must
///   not be used as a foreign key.
///
/// The default project is the single project currently shipped with the app.
/// When a project catalog is introduced, this class is the seam to replace.
class AgricoProject {
  const AgricoProject({
    required this.id,
    required this.code,
    required this.displayName,
  });

  /// Stable identifier. Used for all relationships and cross-references.
  final String id;

  /// Numbering prefix. Not a foreign key.
  final String code;

  /// Human-readable project name.
  final String displayName;

  /// The single project the app ships with today.
  ///
  /// This constant must be used everywhere a project is needed. Do not
  /// generate the id per app start and do not derive it from the code.
  static const AgricoProject defaultProject = AgricoProject(
    id: 'agrico-nong',
    code: 'AGR-NONG',
    displayName: 'AGRICO Nông',
  );
}