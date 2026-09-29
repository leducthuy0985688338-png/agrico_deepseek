import '../../domain/entities/land_parcel.dart';
import '../models/land_parcel_mapper.dart';

abstract final class LandParcelFirestoreMapper {
  static String parcelDocumentPath(LandParcel parcel) =>
      'landParcels/${parcel.id}';

  static String boundaryVersionDocumentPath(
    LandParcelBoundaryVersion version,
  ) => 'landParcels/${version.parcelId}/boundaryVersions/${version.id}';

  static Map<String, Object?> parcelToDocument(LandParcel parcel) =>
      LandParcelMapper.toJson(parcel, includeHistory: false);

  static Map<String, Object?> boundaryVersionToDocument(
    LandParcelBoundaryVersion version,
  ) => LandParcelMapper.boundaryVersionToJson(version);

  static LandParcel parcelFromDocument(
    Map<String, Object?> document,
    Iterable<Map<String, Object?>> boundaryVersions,
  ) => LandParcelMapper.fromJson(document, history: boundaryVersions);
}
