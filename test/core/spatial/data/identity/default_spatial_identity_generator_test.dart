import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:agrico_deepseek/core/spatial/data/identity/default_spatial_identity_generator.dart';

void main() {
  group('DefaultSpatialIdentityGenerator', () {
    test('preserves a normalized caller prefix', () {
      final generator = DefaultSpatialIdentityGenerator(random: Random(1));

      final id = generator.newId('  spatial-feature  ');

      expect(id, startsWith('spatial-feature-'));
      expect(id, isNot(contains(' ')));
    });

    test('generates distinct identities for successive calls', () {
      final generator = DefaultSpatialIdentityGenerator(random: Random(1));

      final first = generator.newId('spatial-revision');
      final second = generator.newId('spatial-revision');

      expect(first, isNot(second));
    });

    test('supports separate spatial identity categories', () {
      final generator = DefaultSpatialIdentityGenerator(random: Random(2));

      expect(
        generator.newId('spatial-feature'),
        startsWith('spatial-feature-'),
      );
      expect(
        generator.newId('spatial-revision'),
        startsWith('spatial-revision-'),
      );
      expect(generator.newId('spatial-link'), startsWith('spatial-link-'));
    });

    test('rejects an empty prefix', () {
      final generator = DefaultSpatialIdentityGenerator(random: Random(3));

      expect(() => generator.newId('   '), throwsA(isA<ArgumentError>()));
    });
  });
}
