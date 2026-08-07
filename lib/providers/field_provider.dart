import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/field_model.dart';

class FieldProvider extends ChangeNotifier {
  List<FieldModel> _fields = [];

  List<FieldModel> get fields => _fields;

  FieldProvider() {
    // Dữ liệu mẫu (bạn có thể thay đổi)
    _fields = [
      FieldModel(
        id: 'LO0001',
        name: 'Lô cà phê A1',
        area: 12500,
        crop: 'Cà phê',
        status: 'Đang trồng',
        polygon: [
          const LatLng(10.8231, 106.6297),
          const LatLng(10.8235, 106.6302),
          const LatLng(10.8229, 106.6305),
          const LatLng(10.8224, 106.6299),
        ],
      ),
      FieldModel(
        id: 'LO0002',
        name: 'Lô tiêu B2',
        area: 8200,
        crop: 'Hồ tiêu',
        status: 'Chuẩn bị thu hoạch',
        polygon: [],
      ),
    ];
  }

  void addField(FieldModel field) {
    _fields.add(field);
    notifyListeners();
  }

  void updateField(FieldModel updated) {
    final index = _fields.indexWhere((f) => f.id == updated.id);
    if (index != -1) {
      _fields[index] = updated;
      notifyListeners();
    }
  }
}
