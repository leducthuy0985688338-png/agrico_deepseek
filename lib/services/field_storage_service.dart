import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/field_model.dart';

class FieldStorageService {
  static const _key = 'agrico_fields_v1';

  Future<List<FieldModel>> loadFields() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];

    return raw.map((item) {
      final json = jsonDecode(item) as Map<String, dynamic>;
      return FieldModel.fromJson(json);
    }).toList();
  }

  Future<void> saveFields(List<FieldModel> fields) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      fields.map((field) => jsonEncode(field.toJson())).toList(),
    );
  }
}
