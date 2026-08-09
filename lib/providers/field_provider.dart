import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';

class FieldProvider extends ChangeNotifier {
  static final FieldProvider instance = FieldProvider._internal();

  factory FieldProvider() => instance;

  FieldProvider._internal() {
    _fields = [
      const FieldModel(
        id: 'LO0001',
        name: 'Lô cà phê A1',
        area: 12500,
        crop: 'Cà phê',
        status: 'Đang trồng',
        polygon: [
          LatLng(10.8231, 106.6297),
          LatLng(10.8235, 106.6302),
          LatLng(10.8229, 106.6305),
          LatLng(10.8224, 106.6299),
        ],
      ),
      const FieldModel(
        id: 'LO0002',
        name: 'Lô tiêu B2',
        area: 8200,
        crop: 'Hồ tiêu',
        status: 'Chuẩn bị thu hoạch',
      ),
    ];
  }

  late List<FieldModel> _fields;

  List<FieldModel> get fields => List.unmodifiable(_fields);

  FieldModel? getFieldById(String id) {
    for (final field in _fields) {
      if (field.id == id) return field;
    }
    return null;
  }

  void updateFieldPhotos(String id, List<String> newPhotoPaths) {
    final index = _fields.indexWhere((f) => f.id == id);
    if (index == -1) return;
    _fields[index] = _fields[index].copyWith(photoPaths: List.unmodifiable(newPhotoPaths));
    notifyListeners();
  }

  void addPhotoToField(String id, String photoPath) {
    final field = getFieldById(id);
    if (field == null) return;
    updateFieldPhotos(id, [...field.photoPaths, photoPath]);
  }

  void addField(FieldModel field) {
    _fields = [..._fields, field];
    notifyListeners();
  }

  void updateField(FieldModel updated) {
    final index = _fields.indexWhere((f) => f.id == updated.id);
    if (index == -1) return;
    _fields[index] = updated;
    notifyListeners();
  }
}
