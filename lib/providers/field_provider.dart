import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';
import '../services/field_storage_service.dart';

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
    _loadPersistedFields();
  }

  final FieldStorageService _storage = FieldStorageService();
  late List<FieldModel> _fields;

  List<FieldModel> get fields => List.unmodifiable(_fields);

  Future<void> _loadPersistedFields() async {
    try {
      final saved = await _storage.loadFields();
      if (saved.isEmpty) return;
      _fields = saved;
      notifyListeners();
    } catch (_) {
      // Keep the built-in demo data if local storage is unavailable/corrupt.
    }
  }

  FieldModel? getFieldById(String id) {
    for (final field in _fields) {
      if (field.id == id) return field;
    }
    return null;
  }

  void updateFieldPhotos(String id, List<String> newPhotoPaths) {
    final index = _fields.indexWhere((f) => f.id == id);
    if (index == -1) return;
    _fields[index] = _fields[index].copyWith(
      photoPaths: List.unmodifiable(newPhotoPaths),
    );
    _persist();
    notifyListeners();
  }

  void addPhotoToField(String id, String photoPath) {
    final field = getFieldById(id);
    if (field == null) return;
    updateFieldPhotos(id, [...field.photoPaths, photoPath]);
  }

  void addField(FieldModel field) {
    _fields = [..._fields, field];
    _persist();
    notifyListeners();
  }

  void updateField(FieldModel updated) {
    final index = _fields.indexWhere((f) => f.id == updated.id);
    if (index == -1) return;
    _fields[index] = updated;
    _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _storage.saveFields(_fields);
    } catch (_) {
      // Persistence must not break field editing when storage fails.
    }
  }
}
