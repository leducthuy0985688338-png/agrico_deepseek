import 'package:flutter/foundation.dart';

import '../models/field_model.dart';
import '../models/field_measurement_history.dart';
import '../services/cloud_service.dart';
import '../services/field_storage_service.dart';

class FieldProvider extends ChangeNotifier {
  static final FieldProvider instance = FieldProvider._internal();
  factory FieldProvider() => instance;
  FieldProvider._internal()
    : _testLoad = null,
      _testSave = null,
      _testDelete = null,
      _testReplace = null,
      _testCloudSave = null,
      _testCloudDelete = null,
      _testBoundarySave = null,
      _testCloudMeasurement = null {
    _fields = [];
    _loadPersistedFields();
  }

  // Only for isolated tests. Never creates a database or calls CloudService.
  FieldProvider.forTest({
    required Future<List<FieldModel>> Function() loadFields,
    required Future<void> Function(FieldModel) saveField,
    required Future<void> Function(String) deleteField,
    Future<void> Function(List<FieldModel>)? replaceFields,
    Future<void> Function(FieldModel)? cloudSaveField,
    Future<void> Function(String)? cloudDelete,
    Future<FieldMeasurementHistory> Function(FieldModel)? saveBoundary,
    Future<void> Function(FieldMeasurementHistory)? cloudMeasurement,
  }) : _testLoad = loadFields,
       _testSave = saveField,
       _testDelete = deleteField,
       _testReplace = replaceFields,
       _testCloudSave = cloudSaveField,
       _testCloudDelete = cloudDelete,
       _testBoundarySave = saveBoundary,
       _testCloudMeasurement = cloudMeasurement {
    _fields = [];
    _loadPersistedFields();
  }

  final FieldStorageService _storage = FieldStorageService();
  final Future<List<FieldModel>> Function()? _testLoad;
  final Future<void> Function(FieldModel)? _testSave;
  final Future<void> Function(String)? _testDelete;
  final Future<void> Function(List<FieldModel>)? _testReplace;
  final Future<void> Function(FieldModel)? _testCloudSave;
  final Future<void> Function(String)? _testCloudDelete;
  final Future<FieldMeasurementHistory> Function(FieldModel)? _testBoundarySave;
  final Future<void> Function(FieldMeasurementHistory)? _testCloudMeasurement;
  Future<void> _cloudTail = Future<void>.value();
  final Map<String, FieldModel> _cloudCandidates = {};
  // Only a successfully persisted restore invalidates older queued deletions.
  final Map<String, Object> _cloudRestoreTokens = {};

  @visibleForTesting
  Future<void> get cloudIdleForTest => _cloudTail;

  late List<FieldModel> _fields;
  bool _isLoading = true;
  bool _hasRestoredFromCloud = false;
  int _localMutationVersion = 0;
  final Map<String, Object> _fieldMutations = {};
  Object? _restoreOperation;

  Object _markFieldMutation(String id) {
    _localMutationVersion++;
    return _fieldMutations[id] = Object();
  }
  Future<void> _writeTail = Future<void>.value();

  // Preserve ordering, but let each caller observe its own write failure.
  // Only the queue tail absorbs errors so subsequent operations still run.
  Future<void> _enqueueWrite(Future<void> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  List<FieldModel> get fields => List.unmodifiable(_fields);
  bool get isLoading => _isLoading;

  Future<void> _loadPersistedFields() async {
    final initialMutationVersion = _localMutationVersion;
    try {
      final saved = await (_testLoad?.call() ?? _storage.loadFields());
      if (saved.isNotEmpty &&
          !_hasRestoredFromCloud &&
          _localMutationVersion == initialMutationVersion) {
        _fields = saved;
      }
    } catch (_) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> restoreFromCloud({required List<FieldModel> fields}) async {
    if (fields.isEmpty) return;

    final restored = <String, FieldModel>{
      for (final field in fields) field.id: field,
    }.values.toList()..sort((a, b) => a.name.compareTo(b.name));

    final previous = List<FieldModel>.of(_fields);
    final previousRestored = _hasRestoredFromCloud;
    final operation = Object();
    _restoreOperation = operation;
    for (final id in {...previous.map((field) => field.id), ...restored.map((field) => field.id)}) {
      _fieldMutations[id] = operation;
    }
    _hasRestoredFromCloud = true;
    _localMutationVersion++;
    _fields = restored;
    notifyListeners();

    try {
      await _enqueueWrite(() async {
        await (_testReplace?.call(restored) ?? _storage.replaceFields(restored));
        _cloudCandidates.clear();
        for (final field in restored) {
          _cloudRestoreTokens[field.id] = Object();
        }
      });
    } catch (_) {
      final previousIds = previous.map((field) => field.id).toSet();
      _fields = [
        for (final field in previous)
          if (identical(_fieldMutations[field.id], operation)) field
          else if (getFieldById(field.id) case final current?) current,
        for (final field in _fields)
          if (!previousIds.contains(field.id) &&
              !identical(_fieldMutations[field.id], operation)) field,
      ];
      if (identical(_restoreOperation, operation)) _hasRestoredFromCloud = previousRestored;
      _localMutationVersion++;
      notifyListeners();
      rethrow;
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
    _markFieldMutation(id);
    _fields[index] = _fields[index].copyWith(
      photoPaths: List.unmodifiable(newPhotoPaths),
    );
    _persistField(_fields[index]);
    notifyListeners();
  }

  void addPhotoToField(String id, String photoPath) {
    final field = getFieldById(id);
    if (field == null) return;
    updateFieldPhotos(id, [...field.photoPaths, photoPath]);
  }

  void addField(FieldModel field) {
    _markFieldMutation(field.id);
    _fields = [..._fields, field];
    _persistField(field);
    _recordMeasurement(field);
    notifyListeners();
  }

  void updateField(FieldModel updated) {
    final index = _fields.indexWhere((f) => f.id == updated.id);
    if (index == -1) return;
    _markFieldMutation(updated.id);
    _fields[index] = updated;
    _persistField(updated);
    _recordMeasurement(updated);
    notifyListeners();
  }

  /// Saves a field to local storage and completes only after SQLite confirms it.
  /// Cloud is scheduled after local success and never delays this Future.
  Future<void> saveFieldLocally(FieldModel field) async {
    await _saveFieldLocally(
      field, () => _testSave?.call(field) ?? _storage.saveField(field),
    );
  }

  Future<void> _saveFieldLocally(
    FieldModel field, Future<void> Function() persist,
  ) async {
    final mutationToken = _markFieldMutation(field.id);
    final index = _fields.indexWhere((existing) => existing.id == field.id);
    final previous = index == -1 ? null : _fields[index];
    if (index == -1) {
      _fields = [..._fields, field];
    } else {
      _fields = [
        for (var i = 0; i < _fields.length; i++)
          if (i == index) field else _fields[i],
      ];
    }
    notifyListeners();
    try {
      await _enqueueWrite(persist);
    } catch (_) {
      // Never overwrite a newer mutation (including a queued deletion).
      final currentIndex = _fields.indexWhere((item) => item.id == field.id);
      if (identical(_fieldMutations[field.id], mutationToken) &&
          currentIndex != -1 &&
          identical(_fields[currentIndex], field)) {
        if (previous == null) {
          _fields = [
            for (final item in _fields)
              if (item.id != field.id) item,
          ];
        } else {
          _fields = [
            for (var i = 0; i < _fields.length; i++)
              if (i == currentIndex) previous else _fields[i],
          ];
        }
        _markFieldMutation(field.id);
        notifyListeners();
      }
      rethrow;
    }
    _cloudCandidates[field.id] = field;
    _scheduleCloudSync(field.id);
  }

  /// Persists boundary and measurement atomically, preserving current metadata.
  Future<void> saveBoundaryLocally(FieldModel boundary) async {
    final current = getFieldById(boundary.id);
    if (current == null) throw StateError('Cannot edit a missing field');
    final field = current.copyWith(
      polygon: List.unmodifiable(boundary.polygon), area: boundary.area,
      perimeter: boundary.perimeter, measurementMethod: boundary.measurementMethod,
      gpsAccuracy: boundary.gpsAccuracy, measuredAt: boundary.measuredAt,
    );
    await _saveMeasuredField(field, create: false);
  }

  Future<void> createMeasuredFieldLocally(FieldModel field) async {
    if (getFieldById(field.id) != null) throw StateError('Field already exists');
    await _saveMeasuredField(field, create: true);
  }

  Future<void> saveFieldPhotosLocally(String id, List<String> paths) async {
    final current = getFieldById(id);
    if (current == null) throw StateError('Field no longer exists');
    await saveFieldLocally(current.copyWith(photoPaths: List.unmodifiable(paths)));
  }

  Future<void> _saveMeasuredField(FieldModel field, {required bool create}) async {
    final restoreToken = _cloudRestoreTokens[field.id];
    late FieldMeasurementHistory measurement;
    await _saveFieldLocally(field, () async {
      if (_testBoundarySave != null) {
        measurement = await _testBoundarySave(field);
      } else if (_testLoad != null) {
        throw StateError('An isolated boundary test requires saveBoundary');
      } else {
        measurement = create
            ? await _storage.createMeasuredFieldLocally(field)
            : await _storage.saveBoundaryLocally(field);
      }
    });
    _enqueueCloud(() async {
      bool isCurrent() => getFieldById(field.id) != null &&
          identical(_cloudRestoreTokens[field.id], restoreToken);
      if (!isCurrent()) return;
      if (_testCloudMeasurement != null) {
        await _testCloudMeasurement(measurement);
      } else if (_testLoad == null) {
        await CloudService.initialize();
        if (!isCurrent()) return;
        await CloudService.saveFieldMeasurement(measurement);
      }
    });
  }

  Future<void> deleteField(String id) async {
    if (_fields.every((field) => field.id != id)) return;
    final restoreToken = _cloudRestoreTokens[id];
    final previous = getFieldById(id)!;
    final previousIndex = _fields.indexOf(previous);
    final mutation = _markFieldMutation(id);
    _fields = _fields.where((field) => field.id != id).toList(growable: false);
    notifyListeners();
    try {
      await _enqueueWrite(() async {
        await (_testDelete?.call(id) ?? _storage.deleteField(id));
        _cloudCandidates.remove(id);
        _enqueueCloud(() async {
          if (!identical(_cloudRestoreTokens[id], restoreToken)) return;
          if (_testCloudDelete != null) {
            await _testCloudDelete(id);
          } else if (_testLoad == null) {
            await CloudService.initialize();
            if (!identical(_cloudRestoreTokens[id], restoreToken)) return;
            await CloudService.deleteField(id);
          }
        });
      });
    } catch (_) {
      if (identical(_fieldMutations[id], mutation) && getFieldById(id) == null) {
        final restored = List<FieldModel>.of(_fields);
        restored.insert(previousIndex < restored.length ? previousIndex : restored.length, previous);
        _fields = restored;
        _markFieldMutation(id);
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> _recordMeasurement(FieldModel field) async {
    if (_testLoad != null ||
        field.polygon.length < 3 ||
        field.measurementMethod == 'unknown') {
      return;
    }
    try {
      await _storage.recordMeasurement(field);
    } catch (_) {}
  }

  Future<void> _enqueueCloud(Future<void> Function() operation) {
    _cloudTail = _cloudTail
        .then((_) => operation())
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return _cloudTail;
  }

  bool _isCurrentCloudCandidate(FieldModel field) =>
      identical(_cloudCandidates[field.id], field) &&
      identical(getFieldById(field.id), field);

  void _scheduleCloudSync(String id) {
    final field = _cloudCandidates[id];
    if (field == null) return;
    _enqueueCloud(() async {
      if (!_isCurrentCloudCandidate(field)) return;
      if (_testCloudSave != null) {
        await _testCloudSave(field);
      } else if (_testLoad == null) {
        await CloudService.initialize();
        if (!_isCurrentCloudCandidate(field)) return;
        await CloudService.saveField(field);
      }
    });
  }

  void _persistField(FieldModel field) {
    _enqueueWrite(() async {
      try {
        await (_testSave?.call(field) ?? _storage.saveField(field));
        _cloudCandidates[field.id] = field;
        _scheduleCloudSync(field.id);
      } catch (_) {}
    });
  }
}
