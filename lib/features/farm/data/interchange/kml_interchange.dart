import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/entities/land_parcel.dart';
import '../../domain/entities/land_survey.dart';
import '../../domain/geometry/wgs84_geometry.dart';

enum KmlInterchangeError {
  malformedXml,
  missingPlacemark,
  missingPolygon,
  invalidCoordinateSyntax,
  invalidGeometry,
  corruptKmz,
  missingKmlDocument,
  invalidTextEncoding,
}

class KmlInterchangeException implements FormatException {
  const KmlInterchangeException(this.error, this.message, [this.cause]);

  final KmlInterchangeError error;

  @override
  final String message;

  final Object? cause;

  @override
  dynamic get source => null;

  @override
  int? get offset => null;

  @override
  String toString() => 'KmlInterchangeException($error): $message';
}

enum ImportPreviewWarning { missingAgricoMetadata }

class AgricoKmlMetadata {
  AgricoKmlMetadata(Map<String, String> values)
    : values = Map.unmodifiable(values);

  static const prefix = 'agrico.';

  final Map<String, String> values;

  bool get hasAgricoMetadata =>
      values.keys.any((key) => key.startsWith(prefix));
  String? get parcelId => values['${prefix}parcelId'];
  String? get parcelCode => values['${prefix}parcelCode'];
  String? get parcelName => values['${prefix}parcelName'];
  String? get farmId => values['${prefix}farmId'];
  String? get householdId => values['${prefix}householdId'];
  String? get householdCode => values['${prefix}householdCode'];
  String? get ownerName => values['${prefix}ownerName'];
  String? get country => values['${prefix}country'];
  String? get province => values['${prefix}province'];
  String? get district => values['${prefix}district'];
  String? get village => values['${prefix}village'];
  String? get landUse => values['${prefix}landUse'];
  String? get currentCondition => values['${prefix}currentCondition'];
  String? get clearingStatus => values['${prefix}clearingStatus'];
  String? get readinessStatus => values['${prefix}readinessStatus'];
  double? get declaredAreaM2 => _double('${prefix}areaM2');
  double? get declaredPerimeterM => _double('${prefix}perimeterM');
  String? get boundarySource => values['${prefix}boundarySource'];
  int? get boundaryVersion => _int('${prefix}boundaryVersion');
  String? get verificationStatus => values['${prefix}verificationStatus'];
  int? get schemaVersion => _int('${prefix}schemaVersion');

  double? _double(String key) => double.tryParse(values[key] ?? '');
  int? _int(String key) => int.tryParse(values[key] ?? '');
}

class LandParcelExchangeMetadata {
  const LandParcelExchangeMetadata({this.household, this.landUseProfile});

  final Household? household;
  final LandUseProfile? landUseProfile;
}

class LandParcelImportPreview {
  LandParcelImportPreview({
    required this.name,
    required this.boundary,
    required this.centroid,
    required this.areaM2,
    required this.perimeterM,
    required this.metadata,
    required this.geometryIndex,
    required List<ImportPreviewWarning> warnings,
  }) : warnings = List.unmodifiable(warnings);

  final String? name;
  final Wgs84Polygon boundary;
  final Wgs84Vertex centroid;
  final double areaM2;
  final double perimeterM;
  final AgricoKmlMetadata metadata;
  final int geometryIndex;
  final List<ImportPreviewWarning> warnings;

  double get areaHa => areaM2 / 10000;
}

class KmlImportDocument {
  KmlImportDocument(List<LandParcelImportPreview> previews)
    : previews = List.unmodifiable(previews);

  final List<LandParcelImportPreview> previews;
}

/// Stateless KML/KMZ adapter. Import only parses, validates and returns preview
/// models; it has no repository access and cannot mutate a [LandParcel].
class KmlInterchangeCodec {
  const KmlInterchangeCodec();

  static const kmlNamespace = 'http://www.opengis.net/kml/2.2';

  String exportKml(
    LandParcel parcel, {
    LandParcelExchangeMetadata metadata = const LandParcelExchangeMetadata(),
  }) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'kml',
      attributes: {'xmlns': kmlNamespace},
      nest: () => builder.element(
        'Document',
        nest: () => builder.element(
          'Placemark',
          nest: () {
            builder.element('name', nest: parcel.name);
            _writeExtendedData(builder, parcel, metadata);
            builder.element(
              'Polygon',
              nest: () {
                builder.element('tessellate', nest: '1');
                builder.element(
                  'outerBoundaryIs',
                  nest: () => builder.element(
                    'LinearRing',
                    nest: () => builder.element(
                      'coordinates',
                      nest: parcel.boundary.vertices.map(_coordinate).join(' '),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    return builder.buildDocument().toXmlString(pretty: true);
  }

  Uint8List exportKmz(
    LandParcel parcel, {
    LandParcelExchangeMetadata metadata = const LandParcelExchangeMetadata(),
  }) {
    final bytes = utf8.encode(exportKml(parcel, metadata: metadata));
    final archive = Archive()
      ..addFile(ArchiveFile('doc.kml', bytes.length, bytes));
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const KmlInterchangeException(
        KmlInterchangeError.corruptKmz,
        'Unable to create the KMZ archive.',
      );
    }
    return Uint8List.fromList(encoded);
  }

  KmlImportDocument importKmz(Uint8List bytes) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (error) {
      throw KmlInterchangeException(
        KmlInterchangeError.corruptKmz,
        'The KMZ archive is corrupt or unsupported.',
        error,
      );
    }

    final kmlFiles = archive.files
        .where(
          (file) => file.isFile && file.name.toLowerCase().endsWith('.kml'),
        )
        .toList(growable: false);
    if (kmlFiles.isEmpty) {
      throw const KmlInterchangeException(
        KmlInterchangeError.missingKmlDocument,
        'The KMZ archive does not contain a KML document.',
      );
    }
    final selected = kmlFiles.firstWhere(
      (file) =>
          file.name.replaceAll('\\', '/').toLowerCase().split('/').last ==
          'doc.kml',
      orElse: () => kmlFiles.first,
    );

    try {
      final content = selected.content;
      final kmlBytes = content is Uint8List
          ? content
          : Uint8List.fromList((content as List).cast<int>());
      return importKml(utf8.decode(kmlBytes));
    } on KmlInterchangeException {
      rethrow;
    } on FormatException catch (error) {
      throw KmlInterchangeException(
        KmlInterchangeError.invalidTextEncoding,
        'The KML document in the KMZ archive is not valid UTF-8.',
        error,
      );
    } catch (error) {
      throw KmlInterchangeException(
        KmlInterchangeError.corruptKmz,
        'The KML document could not be read from the KMZ archive.',
        error,
      );
    }
  }

  KmlImportDocument importKml(String source) {
    late final XmlDocument document;
    try {
      document = XmlDocument.parse(source);
    } catch (error) {
      throw KmlInterchangeException(
        KmlInterchangeError.malformedXml,
        'The KML document is not well-formed XML.',
        error,
      );
    }

    final placemarks = _elements(document, 'Placemark').toList(growable: false);
    if (placemarks.isEmpty) {
      throw const KmlInterchangeException(
        KmlInterchangeError.missingPlacemark,
        'The KML document does not contain a Placemark.',
      );
    }

    final previews = <LandParcelImportPreview>[];
    for (final placemark in placemarks) {
      final polygons = _elements(placemark, 'Polygon').toList(growable: false);
      final name = _directChildText(placemark, 'name');
      final metadata = _readExtendedData(placemark);
      for (var index = 0; index < polygons.length; index++) {
        previews.add(_preview(name, metadata, polygons[index], index));
      }
    }
    if (previews.isEmpty) {
      throw const KmlInterchangeException(
        KmlInterchangeError.missingPolygon,
        'No Polygon geometry was found in any Placemark.',
      );
    }
    return KmlImportDocument(previews);
  }

  LandParcelImportPreview _preview(
    String? name,
    AgricoKmlMetadata metadata,
    XmlElement polygonElement,
    int geometryIndex,
  ) {
    final outerBoundary = _elements(
      polygonElement,
      'outerBoundaryIs',
    ).firstOrNull;
    final coordinates = outerBoundary == null
        ? null
        : _elements(outerBoundary, 'coordinates').firstOrNull?.innerText;
    if (coordinates == null || coordinates.trim().isEmpty) {
      throw const KmlInterchangeException(
        KmlInterchangeError.invalidCoordinateSyntax,
        'A Polygon exterior ring is missing coordinates.',
      );
    }

    late final Wgs84Polygon boundary;
    try {
      boundary = Wgs84Polygon.fromVertices(_parseCoordinates(coordinates));
    } on PolygonValidationException catch (error) {
      throw KmlInterchangeException(
        KmlInterchangeError.invalidGeometry,
        error.message,
        error,
      );
    }
    late final Wgs84PolygonMetrics metrics;
    try {
      metrics = const Wgs84GeometryService().measure(boundary);
    } on PolygonValidationException catch (error) {
      throw KmlInterchangeException(
        KmlInterchangeError.invalidGeometry,
        error.message,
        error,
      );
    }

    return LandParcelImportPreview(
      name: name,
      boundary: boundary,
      centroid: metrics.centroid,
      areaM2: metrics.areaM2,
      perimeterM: metrics.perimeterM,
      metadata: metadata,
      geometryIndex: geometryIndex,
      warnings: [
        if (!metadata.hasAgricoMetadata)
          ImportPreviewWarning.missingAgricoMetadata,
      ],
    );
  }

  List<Wgs84Vertex> _parseCoordinates(String source) {
    final vertices = <Wgs84Vertex>[];
    for (final token in source.trim().split(RegExp(r'\s+'))) {
      final parts = token.split(',');
      if (parts.length < 2 || parts.length > 3) {
        throw const KmlInterchangeException(
          KmlInterchangeError.invalidCoordinateSyntax,
          'KML coordinates must use longitude,latitude[,altitude] order.',
        );
      }
      final longitude = double.tryParse(parts[0].trim());
      final latitude = double.tryParse(parts[1].trim());
      final altitude = parts.length == 3 && parts[2].trim().isNotEmpty
          ? double.tryParse(parts[2].trim())
          : null;
      if (longitude == null ||
          latitude == null ||
          (parts.length == 3 &&
              parts[2].trim().isNotEmpty &&
              altitude == null)) {
        throw const KmlInterchangeException(
          KmlInterchangeError.invalidCoordinateSyntax,
          'A KML coordinate contains a non-numeric value.',
        );
      }
      vertices.add(
        Wgs84Vertex(
          latitude: latitude,
          longitude: longitude,
          altitudeM: altitude,
        ),
      );
    }
    return vertices;
  }

  static String _coordinate(Wgs84Vertex vertex) =>
      '${vertex.longitude},${vertex.latitude},${vertex.altitudeM ?? 0.0}';

  static Iterable<XmlElement> _elements(XmlNode node, String localName) => node
      .descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName);

  static String? _directChildText(XmlElement element, String localName) {
    final child = element.children.whereType<XmlElement>().firstWhere(
      (item) => item.name.local == localName,
      orElse: () => XmlElement(XmlName('_missing')),
    );
    return child.name.local == '_missing' ? null : child.innerText.trim();
  }

  static AgricoKmlMetadata _readExtendedData(XmlElement placemark) {
    final values = <String, String>{};
    for (final data in _elements(placemark, 'Data')) {
      final name = data.getAttribute('name')?.trim();
      final value = _elements(data, 'value').firstOrNull?.innerText.trim();
      if (name != null && name.isNotEmpty && value != null) {
        values[name] = value;
      }
    }
    return AgricoKmlMetadata(values);
  }

  static void _writeExtendedData(
    XmlBuilder builder,
    LandParcel parcel,
    LandParcelExchangeMetadata metadata,
  ) {
    final household = metadata.household;
    final landUse = metadata.landUseProfile;
    final values = <String, Object?>{
      '${AgricoKmlMetadata.prefix}parcelId': parcel.id,
      '${AgricoKmlMetadata.prefix}parcelCode': parcel.parcelCode,
      '${AgricoKmlMetadata.prefix}parcelName': parcel.name,
      '${AgricoKmlMetadata.prefix}farmId': parcel.farmId,
      '${AgricoKmlMetadata.prefix}householdId': parcel.ownerHouseholdId,
      '${AgricoKmlMetadata.prefix}householdCode': household?.householdCode,
      '${AgricoKmlMetadata.prefix}ownerName': household?.headOfHouseholdName,
      '${AgricoKmlMetadata.prefix}country':
          household?.administrativeLocation.countryName,
      '${AgricoKmlMetadata.prefix}province':
          household?.administrativeLocation.provinceName,
      '${AgricoKmlMetadata.prefix}district':
          household?.administrativeLocation.districtName,
      '${AgricoKmlMetadata.prefix}village':
          household?.administrativeLocation.villageName,
      '${AgricoKmlMetadata.prefix}landUse': landUse?.landUseType.name,
      '${AgricoKmlMetadata.prefix}currentCondition':
          landUse?.currentCondition.name,
      '${AgricoKmlMetadata.prefix}clearingStatus': landUse?.clearingStatus.name,
      '${AgricoKmlMetadata.prefix}readinessStatus':
          landUse?.readinessStatus.name,
      '${AgricoKmlMetadata.prefix}areaM2': parcel.areaM2,
      '${AgricoKmlMetadata.prefix}areaHa': parcel.areaHa,
      '${AgricoKmlMetadata.prefix}perimeterM': parcel.perimeterM,
      '${AgricoKmlMetadata.prefix}boundarySource': parcel.boundarySource.name,
      '${AgricoKmlMetadata.prefix}boundaryVersion': parcel.boundaryVersion,
      '${AgricoKmlMetadata.prefix}verificationStatus':
          parcel.verificationStatus.name,
      '${AgricoKmlMetadata.prefix}schemaVersion': parcel.schemaVersion,
    };
    builder.element(
      'ExtendedData',
      nest: () {
        for (final entry in values.entries.where(
          (entry) => entry.value != null,
        )) {
          builder.element(
            'Data',
            attributes: {'name': entry.key},
            nest: () => builder.element('value', nest: entry.value.toString()),
          );
        }
      },
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
