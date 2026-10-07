import 'package:flutter/foundation.dart';

import '../../../../core/permissions/authorization.dart';
import '../../application/farm_task_service.dart';
import '../../domain/entities/farm_task.dart';

class FarmTaskController extends ChangeNotifier {
  FarmTaskController({required this.subject, required this.service});

  final AuthorizationSubject subject;
  final FarmTaskService service;

  List<FarmTask> items = const [];
  bool loading = false;
  bool hasError = false;

  Future<void> load() async {
    loading = true;
    hasError = false;
    notifyListeners();
    try {
      items = await service.list(subject);
    } catch (_) {
      hasError = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> create(FarmTask task) async {
    await service.create(subject, task);
    await load();
  }

  Future<void> update(FarmTask task) async {
    await service.update(subject, task);
    await load();
  }

  Future<void> changeStatus(String taskId, FarmTaskStatus status) async {
    await service.changeStatus(subject, taskId, status);
    await load();
  }

  Future<void> complete(String taskId) async {
    await service.complete(subject, taskId);
    await load();
  }
}
