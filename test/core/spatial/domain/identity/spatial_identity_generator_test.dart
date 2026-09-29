import 'package:flutter_test/flutter_test.dart';

import '../../support/sequential_spatial_identity_generator.dart';

void main() {
  group('SequentialSpatialIdentityGenerator', () {
    test('generates deterministic sequential identities', () {
      final generator = SequentialSpatialIdentityGenerator();

      expect(generator.newId('spatial-feature'), 'spatial-feature-1');
      expect(generator.newId('spatial-revision'), 'spatial-revision-2');
      expect(generator.newId('spatial-link'), 'spatial-link-3');
    });

    test('continues from an explicit initial value', () {
      final generator = SequentialSpatialIdentityGenerator(initialValue: 40);

      expect(generator.newId('spatial-feature'), 'spatial-feature-41');
      expect(generator.newId('spatial-feature'), 'spatial-feature-42');
    });

    test('trims the prefix before generating the identity', () {
      final generator = SequentialSpatialIdentityGenerator();

      expect(generator.newId('  spatial-feature  '), 'spatial-feature-1');
    });

    test('rejects an empty prefix without consuming a sequence value', () {
      final generator = SequentialSpatialIdentityGenerator();

      expect(() => generator.newId('   '), throwsA(isA<ArgumentError>()));

      expect(generator.newId('spatial-feature'), 'spatial-feature-1');
    });

    test('rejects a negative initial value', () {
      expect(
        () => SequentialSpatialIdentityGenerator(initialValue: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('uses queued identities for a matching prefix', () {
      final generator = SequentialSpatialIdentityGenerator(
        queuedIds: {
          'spatial-revision': ['shared-revision-id', 'shared-revision-id'],
        },
      );

      expect(generator.newId('spatial-revision'), 'shared-revision-id');
      expect(generator.newId('spatial-revision'), 'shared-revision-id');
    });

    test('queued identities do not consume the fallback sequence', () {
      final generator = SequentialSpatialIdentityGenerator(
        queuedIds: {
          'spatial-link': ['link-shared'],
        },
      );

      expect(generator.newId('spatial-link'), 'link-shared');
      expect(generator.newId('spatial-feature'), 'spatial-feature-1');
    });

    test('falls back to sequential identities after a queue is exhausted', () {
      final generator = SequentialSpatialIdentityGenerator(
        initialValue: 9,
        queuedIds: {
          'spatial-feature': ['forced-feature-id'],
        },
      );

      expect(generator.newId('spatial-feature'), 'forced-feature-id');
      expect(generator.newId('spatial-feature'), 'spatial-feature-10');
    });

    test('keeps queued identities isolated by normalized prefix', () {
      final generator = SequentialSpatialIdentityGenerator(
        queuedIds: {
          'spatial-link': ['forced-link'],
          'spatial-revision': ['forced-revision'],
        },
      );

      expect(generator.newId('  spatial-link  '), 'forced-link');
      expect(generator.newId('spatial-revision'), 'forced-revision');
      expect(generator.newId('spatial-feature'), 'spatial-feature-1');
    });
  });
}
