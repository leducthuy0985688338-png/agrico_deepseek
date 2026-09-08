import 'dart:convert';
import 'dart:typed_data';

import 'package:agrico_deepseek/features/farm/data/interchange/kml_interchange.dart';
import 'package:agrico_deepseek/features/farm/domain/entities/land_parcel.dart';
import 'package:agrico_deepseek/features/farm/domain/geometry/wgs84_geometry.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = KmlInterchangeCodec();
  final timestamp = DateTime.utc(2026, 9, 8, 3);

  LandParcel parcel({String name = 'Lô ກະສິກຳ North'}) => LandParcel.create(
    id: 'parcel-1',
    farmId: 'farm-1',
    parcelCode: 'VN-ລາວ-EN-01',
    name: name,
    boundary: Wgs84Polygon.fromVertices(const [
      Wgs84Vertex(latitude: 16.5, longitude: 104.7, altitudeM: 120),
      Wgs84Vertex(latitude: 16.5, longitude: 104.701, altitudeM: 121),
      Wgs84Vertex(latitude: 16.501, longitude: 104.701, altitudeM: 122),
      Wgs84Vertex(latitude: 16.501, longitude: 104.7, altitudeM: 123),
    ]),
    boundarySource: BoundarySource.gps,
    verificationStatus: BoundaryVerificationStatus.measured,
    actorMembershipId: 'member-1',
    occurredAt: timestamp,
  );

  test('LandParcel to KML to preview preserves geometry and metadata', () {
    final source = parcel();
    final kml = codec.exportKml(source);
    final document = codec.importKml(kml);

    expect(document.previews, hasLength(1));
    final preview = document.previews.single;
    expect(preview.boundary, source.boundary);
    expect(preview.areaM2, closeTo(source.areaM2, 0.001));
    expect(preview.perimeterM, closeTo(source.perimeterM, 0.001));
    expect(preview.metadata.parcelId, source.id);
    expect(preview.metadata.parcelCode, source.parcelCode);
    expect(preview.metadata.parcelName, source.name);
    expect(preview.metadata.farmId, source.farmId);
    expect(preview.metadata.boundarySource, 'gps');
    expect(preview.metadata.boundaryVersion, 1);
    expect(preview.metadata.verificationStatus, 'measured');
    expect(preview.metadata.schemaVersion, LandParcel.currentSchemaVersion);
    expect(preview.warnings, isEmpty);
  });

  test('exports coordinates in longitude latitude altitude order', () {
    final kml = codec.exportKml(parcel());

    expect(kml, contains('104.7,16.5,120.0'));
    expect(kml, isNot(contains('16.5,104.7')));
  });

  test('imports longitude latitude order and preserves altitude', () {
    final preview = codec
        .importKml(
          _kml('''
      <Polygon><outerBoundaryIs><LinearRing><coordinates>
        104.7,16.5,120 104.701,16.5,121 104.7,16.501,122
      </coordinates></LinearRing></outerBoundaryIs></Polygon>
    '''),
        )
        .previews
        .single;

    expect(preview.boundary.vertices.first.latitude, 16.5);
    expect(preview.boundary.vertices.first.longitude, 104.7);
    expect(preview.boundary.vertices.first.altitudeM, 120);
    expect(preview.boundary.isClosed, isTrue);
  });

  test('rejects malformed XML with a clear domain error', () {
    expect(
      () => codec.importKml('<kml><Placemark>'),
      throwsA(_error(KmlInterchangeError.malformedXml)),
    );
  });

  test('rejects invalid coordinates through the geometry validator', () {
    expect(
      () => codec.importKml(
        _kml('''
        <Polygon><outerBoundaryIs><LinearRing><coordinates>
          200,16.5 104.701,16.5 104.7,16.501
        </coordinates></LinearRing></outerBoundaryIs></Polygon>
      '''),
      ),
      throwsA(_error(KmlInterchangeError.invalidGeometry)),
    );
  });

  test('rejects self-intersection through the geometry validator', () {
    expect(
      () => codec.importKml(
        _kml('''
        <Polygon><outerBoundaryIs><LinearRing><coordinates>
          104.7,16.5 104.701,16.501 104.7,16.501 104.701,16.5
        </coordinates></LinearRing></outerBoundaryIs></Polygon>
      '''),
      ),
      throwsA(_error(KmlInterchangeError.invalidGeometry)),
    );
  });

  test('imports every Polygon in a MultiGeometry', () {
    final document = codec.importKml(
      _kml('''
      <MultiGeometry>
        ${_triangle(104.7, 16.5)}
        ${_triangle(104.8, 16.6)}
      </MultiGeometry>
    '''),
    );

    expect(document.previews, hasLength(2));
    expect(document.previews[0].geometryIndex, 0);
    expect(document.previews[1].geometryIndex, 1);
  });

  test('round trips Unicode Vietnamese Lao and English text', () {
    final source = parcel(name: 'Lúa mùa • ເຂົ້ານາ • Rice field');
    final preview = codec.importKml(codec.exportKml(source)).previews.single;

    expect(preview.name, source.name);
    expect(preview.metadata.parcelName, source.name);
  });

  test('accepts ordinary Google Earth KML without AGRICO metadata', () {
    final preview = codec
        .importKml(_kml(_triangle(104.7, 16.5), name: 'Google Earth field'))
        .previews
        .single;

    expect(preview.name, 'Google Earth field');
    expect(preview.metadata.hasAgricoMetadata, isFalse);
    expect(
      preview.warnings,
      contains(ImportPreviewWarning.missingAgricoMetadata),
    );
  });

  test('KMZ round trip reads doc.kml', () {
    final source = parcel();
    final kmz = codec.exportKmz(source);
    final preview = codec.importKmz(kmz).previews.single;

    expect(preview.boundary, source.boundary);
    expect(preview.metadata.parcelId, source.id);
  });

  test('reports corrupt KMZ and archive without a KML document', () {
    expect(
      () => codec.importKmz(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(_error(KmlInterchangeError.corruptKmz)),
    );

    final archive = Archive()
      ..addFile(ArchiveFile('readme.txt', 5, utf8.encode('hello')));
    final withoutKml = Uint8List.fromList(ZipEncoder().encode(archive)!);
    expect(
      () => codec.importKmz(withoutKml),
      throwsA(_error(KmlInterchangeError.missingKmlDocument)),
    );
  });
}

Matcher _error(KmlInterchangeError error) => isA<KmlInterchangeException>()
    .having((exception) => exception.error, 'error', error);

String _kml(String geometry, {String name = 'Field'}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document><Placemark><name>$name</name>$geometry</Placemark></Document>
</kml>
''';

String _triangle(double longitude, double latitude) =>
    '''
<Polygon><outerBoundaryIs><LinearRing><coordinates>
  $longitude,$latitude ${longitude + 0.001},$latitude $longitude,${latitude + 0.001}
</coordinates></LinearRing></outerBoundaryIs></Polygon>
''';
