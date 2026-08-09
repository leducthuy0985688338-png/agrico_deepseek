import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/field_model.dart';
import '../services/cloud_service.dart';
import '../services/field_storage_service.dart';

class FieldProvider extends ChangeNotifier {
  static final FieldProvider instance = FieldProvider._internal();
  factory FieldProvider() => instance;
  FieldProvider._internal() {
    _fields = _demoFields;
    _loadPersistedFields();
  }

  final FieldStorageService _storage = FieldStorageService();
  late List<FieldModel> _fields;
  bool _isLoading = true;

  List<FieldModel> get fields => List.unmodifiable(_fields);
  bool get isLoading => _isLoading;

  static const _demoFields = [
    FieldModel(id: 'LO0001', name: 'Lô cà phê A1', area: 12500, crop: 'Cà phê', status: 'Đang trồng', perimeter: 450, measurementMethod: 'demo', polygon: [LatLng(10.8231, 106.6297), LatLng(10.8235, 106.6302), LatLng(10.8229, 106.6305), LatLng(10.8224, 106.6299)]),
    FieldModel(id: 'LO0002', name: 'Lô tiêu B2', area: 8200, crop: 'Hồ tiêu', status: 'Chuẩn bị thu hoạch'),
  ];

  Future<void> _loadPersistedFields() async {
    try {
      final saved = await _storage.loadFields();
      if (saved.isNotEmpty) _fields = saved;
    } catch (_) {} finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  FieldModel? getFieldById(String id) {
    for (final field in _fields) { if (field.id == id) return field; }
    return null;
  }

  void updateFieldPhotos(String id, List<String> newPhotoPaths) {
    final index = _fields.indexWhere((f) => f.id == id);
    if (index == -1) return;
    _fields[index] = _fields[index].copyWith(photoPaths: List.unmodifiable(newPhotoPaths));
    _persistField(_fields[index]);
    notifyListeners();
  }

  void addPhotoToField(String id, String photoPath) {
    final field = getFieldById(id);
    if (field == null) return;
    updateFieldPhotos(id, [...field.photoPaths, photoPath]);
  }

  void addField(FieldModel field) {
    _fields = [..._fields, field];
    _persistField(field);
    notifyListeners();
  }

  void updateField(FieldModel updated) {
    final index = _fields.indexWhere((f) => f.id == updated.id);
    if (index == -1) return;
    _fields[index] = updated;
    _persistField(updated);
    notifyListeners();
  }

  Future<void> deleteField(String id) async {
    if (_fields.every((field) => field.id != id)) return;
    _fields = _fields.where((field) => field.id != id).toList(growable: false);
    try { await _storage.deleteField(id); } catch (_) {}
    try { await CloudService.initialize(); await CloudService.deleteField(id); } catch (_) {}
    notifyListeners();
  }

  Future<void> _persistField(FieldModel field) async {
    try { await _storage.saveField(field); } catch (_) {}
    try { await CloudService.initialize(); await CloudService.saveField(field); } catch (_) {}
  }
}
