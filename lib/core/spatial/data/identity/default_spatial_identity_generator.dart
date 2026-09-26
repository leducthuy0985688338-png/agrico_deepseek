import 'dart:math';

import '../../domain/identity/spatial_identity_generator.dart';

final class DefaultSpatialIdentityGenerator
    implements SpatialIdentityGenerator {
  DefaultSpatialIdentityGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String newId(String prefix) {
    final normalizedPrefix = prefix.trim();

    if (normalizedPrefix.isEmpty) {
      throw ArgumentError.value(prefix, 'prefix', 'must not be empty');
    }

    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomPart = _random
        .nextInt(0x7fffffff)
        .toRadixString(16)
        .padLeft(8, '0');

    return '$normalizedPrefix-$timestamp-$randomPart';
  }
}
