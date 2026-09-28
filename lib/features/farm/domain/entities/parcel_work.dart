/// Resources are AGRICO project resources, never household records. Their IDs
/// remain stable when the display name changes.
enum WorkResourceKind { machine, worker }

class WorkResource {
  const WorkResource({
    required this.id, required this.farmId, required this.kind,
    required this.code, required this.name, this.active = true,
  });

  final String id;
  final String farmId;
  final WorkResourceKind kind;
  final String code;
  final String name;
  final bool active;

  void validate() {
    if (id.trim().isEmpty || farmId.trim().isEmpty || code.trim().isEmpty ||
        name.trim().isEmpty) {
      throw const FormatException('Resource identity and name are required.');
    }
  }
}

/// Work belongs to a particular parcel and phase. Machine and worker IDs
/// describe the crew for this operation, not a permanent parcel attribute.
enum ParcelWorkPhase { clearing, cultivation }

class ParcelWorkEvent {
  ParcelWorkEvent({
    required this.id, required this.farmId, required this.parcelId,
    required this.phase, required this.description,
    required this.occurredAt, required this.actorMembershipId,
    required List<String> machineIds, required List<String> workerIds,
    this.areaM2, this.notes,
  }) : machineIds = List.unmodifiable(machineIds),
       workerIds = List.unmodifiable(workerIds);

  final String id;
  final String farmId;
  final String parcelId;
  final ParcelWorkPhase phase;
  final String description;
  final DateTime occurredAt;
  final String actorMembershipId;
  final List<String> machineIds;
  final List<String> workerIds;
  final double? areaM2;
  final String? notes;

  void validate() {
    if ([id, farmId, parcelId, description, actorMembershipId]
        .any((value) => value.trim().isEmpty)) {
      throw const FormatException('Parcel work identity and description are required.');
    }
    if (machineIds.isEmpty && workerIds.isEmpty) {
      throw const FormatException('A machine or worker is required.');
    }
    if (machineIds.any((id) => id.trim().isEmpty) ||
        workerIds.any((id) => id.trim().isEmpty) ||
        machineIds.toSet().length != machineIds.length ||
        workerIds.toSet().length != workerIds.length) {
      throw const FormatException('Work resource IDs must be unique and nonblank.');
    }
    if (areaM2 != null && (!areaM2!.isFinite || areaM2! <= 0)) {
      throw const FormatException('Worked area must be positive and finite.');
    }
    if (notes != null && notes!.trim().isEmpty) {
      throw const FormatException('Work notes cannot be blank.');
    }
  }
}
