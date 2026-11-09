import 'package:agrico_deepseek/core/spatial/domain/identity/spatial_identity_generator.dart';

final class ScriptedSpatialIdentity {
  const ScriptedSpatialIdentity({required this.prefix, required this.id});

  final String prefix;
  final String id;
}

final class ScriptedSpatialIdentityGenerator
    implements SpatialIdentityGenerator {
  ScriptedSpatialIdentityGenerator(Iterable<ScriptedSpatialIdentity> identities)
    : _identities = List<ScriptedSpatialIdentity>.of(identities);

  final List<ScriptedSpatialIdentity> _identities;
  int _index = 0;

  int get consumedCount => _index;

  int get remainingCount => _identities.length - _index;

  @override
  String newId(String prefix) {
    if (_index >= _identities.length) {
      throw StateError(
        'No scripted Spatial identity remains for prefix $prefix.',
      );
    }

    final scripted = _identities[_index];

    if (scripted.prefix != prefix) {
      throw StateError(
        'Expected Spatial identity prefix ${scripted.prefix}, '
        'but received $prefix at index $_index.',
      );
    }

    _index += 1;
    return scripted.id;
  }
}
