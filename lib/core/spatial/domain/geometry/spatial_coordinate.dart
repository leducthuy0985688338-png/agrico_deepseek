/// Canonical WGS84 coordinate used by Spatial Core.
///
/// Domain code uses latitude/longitude naming to avoid ambiguity.
/// External formats such as KML may use a different coordinate order.
class SpatialCoordinate {
  const SpatialCoordinate({
    required this.latitude,
    required this.longitude,
    this.altitudeM,
  });

  /// Latitude in decimal degrees, valid from -90 to 90.
  final double latitude;

  /// Longitude in decimal degrees, valid from -180 to 180.
  final double longitude;

  /// Optional altitude in metres.
  final double? altitudeM;

  /// Longitude exposed explicitly for KML coordinate order.
  double get kmlLongitude => longitude;

  /// Latitude exposed explicitly for KML coordinate order.
  double get kmlLatitude => latitude;

  /// Optional altitude exposed explicitly for KML coordinate order.
  double? get kmlAltitudeM => altitudeM;

  void validate() {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw const FormatException(
        'Spatial coordinate latitude must be finite and between -90 and 90.',
      );
    }

    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw const FormatException(
        'Spatial coordinate longitude must be finite and between -180 and 180.',
      );
    }

    if (altitudeM != null && !altitudeM!.isFinite) {
      throw const FormatException(
        'Spatial coordinate altitude must be finite when provided.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpatialCoordinate &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          altitudeM == other.altitudeM;

  @override
  int get hashCode => Object.hash(latitude, longitude, altitudeM);

  @override
  String toString() =>
      'SpatialCoordinate('
      'latitude: $latitude, '
      'longitude: $longitude, '
      'altitudeM: $altitudeM'
      ')';
}
