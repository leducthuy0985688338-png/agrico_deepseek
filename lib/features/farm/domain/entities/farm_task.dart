enum FarmTaskStatus { pending, inProgress, completed, delayed }

/// A farm-scoped task. Resource IDs refer to the parcel work catalog.
class FarmTask {
  const FarmTask({
    required this.id,
    required this.farmId,
    required this.title,
    required this.description,
    required this.status,
    required this.dueAt,
    required this.createdAt,
    this.parcelId,
    this.workerResourceId,
    this.machineResourceId,
  });

  final String id;
  final String farmId;
  final String title;
  final String description;
  final FarmTaskStatus status;
  final DateTime dueAt;
  final DateTime createdAt;
  final String? parcelId;
  final String? workerResourceId;
  final String? machineResourceId;

  void validate() {
    if (id.trim().isEmpty ||
        farmId.trim().isEmpty ||
        title.trim().isEmpty ||
        [
          parcelId,
          workerResourceId,
          machineResourceId,
        ].whereType<String>().any((id) => id.trim().isEmpty)) {
      throw const FormatException(
        'Task identity, title and links must be valid.',
      );
    }
  }
}
