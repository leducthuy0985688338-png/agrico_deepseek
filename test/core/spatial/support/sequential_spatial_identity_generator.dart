import 'dart:collection';

import 'package:agrico_deepseek/core/spatial/domain/identity/spatial_identity_generator.dart';

final class SequentialSpatialIdentityGenerator
    implements SpatialIdentityGenerator {
  SequentialSpatialIdentityGenerator({
    int initialValue = 0,
    Map<String, Iterable<String>> queuedIds = const {},
  }) : _nextValue = initialValue,
       _queuedIds = {
         for (final entry in queuedIds.entries)
           entry.key: Queue<String>.from(entry.value),
       } {
    if (initialValue < 0) {
      throw ArgumentError.value(
        initialValue,
        'initialValue',
        'must not be negative',
      );
    }
  }

  int _nextValue;
  final Map<String, Queue<String>> _queuedIds;

  @override
  String newId(String prefix) {
    final normalizedPrefix = prefix.trim();

    if (normalizedPrefix.isEmpty) {
      throw ArgumentError.value(prefix, 'prefix', 'must not be empty');
    }

    final queued = _queuedIds[normalizedPrefix];

    if (queued != null && queued.isNotEmpty) {
      return queued.removeFirst();
    }

    _nextValue += 1;
    return '$normalizedPrefix-$_nextValue';
  }
}
