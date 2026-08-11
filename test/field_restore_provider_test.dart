import 'package:agrico_deepseek/models/field_model.dart';
import 'package:agrico_deepseek/providers/field_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('field cloud round trip keeps the full GPS boundary', () {
    final measuredAt = DateTime.utc(2026, 8, 11, 6, 45);
    final source = FieldModel(
      id: 'LO-CLOUD',
      name: 'Lô Cloud',
      area: 12543.75,
      crop: 'Cây lạc',
      status: 'Đang trồng',
      polygon: const [
        LatLng(16.4761, 105.1992),
        LatLng(16.4770, 105.2004),
        LatLng(16.4758, 105.2011),
        LatLng(16.4749, 105.1998),
      ],
      photoPaths: const ['/cloud/field-a.jpg'],
      perimeter: 468.25,
      measurementMethod: 'gps',
      gpsAccuracy: 2.8,
      measuredAt: measuredAt,
    );

    final restored = FieldModel.fromJson(source.toJson());

    expect(restored.id, source.id);
    expect(restored.name, source.name);
    expect(restored.area, source.area);
    expect(restored.crop, source.crop);
    expect(restored.status, source.status);
    expect(restored.polygon, hasLength(4));
    expect(restored.polygon[2].latitude, closeTo(16.4758, 0.000001));
    expect(restored.polygon[2].longitude, closeTo(105.2011, 0.000001));
    expect(restored.perimeter, 468.25);
    expect(restored.measurementMethod, 'gps');
    expect(restored.gpsAccuracy, 2.8);
    expect(restored.measuredAt, measuredAt);
    expect(restored.photoPaths, ['/cloud/field-a.jpg']);
  });

  test('field restore replaces samples, deduplicates, and ignores empty cloud', () async {
    final provider = FieldProvider();
    final field = FieldModel(
      id: 'LO-CLOUD',
      name: 'Lô Cloud',
      area: 12543.75,
      crop: 'Cây lạc',
      status: 'Đang trồng',
      polygon: const [
        LatLng(16.4761, 105.1992),
        LatLng(16.4770, 105.2004),
        LatLng(16.4758, 105.2011),
      ],
      perimeter: 420,
      measurementMethod: 'gps',
      gpsAccuracy: 3.1,
      measuredAt: DateTime.utc(2026, 8, 11),
    );

    await provider.restoreFromCloud(fields: [field, field]);

    expect(provider.fields, hasLength(1));
    expect(provider.fields.single.id, 'LO-CLOUD');
    expect(provider.fields.single.polygon, hasLength(3));
    expect(provider.fields.single.measurementMethod, 'gps');

    final idsAfterRestore = provider.fields.map((item) => item.id).toList();
    await provider.restoreFromCloud(fields: const []);

    expect(provider.fields.map((item) => item.id), idsAfterRestore);
  });
}
