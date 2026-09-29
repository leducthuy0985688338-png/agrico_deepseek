import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_spatial_identity_generator.dart';

void main() {
  test('returns scripted identities in order', () {
    final generator = ScriptedSpatialIdentityGenerator([
      const ScriptedSpatialIdentity(prefix: 'spatial-link', id: 'link-1'),
      const ScriptedSpatialIdentity(prefix: 'spatial-feature', id: 'feature-1'),
      const ScriptedSpatialIdentity(
        prefix: 'spatial-revision',
        id: 'revision-1',
      ),
    ]);

    expect(generator.newId('spatial-link'), 'link-1');
    expect(generator.newId('spatial-feature'), 'feature-1');
    expect(generator.newId('spatial-revision'), 'revision-1');
    expect(generator.consumedCount, 3);
    expect(generator.remainingCount, 0);
  });

  test('rejects unexpected prefix without consuming identity', () {
    final generator = ScriptedSpatialIdentityGenerator([
      const ScriptedSpatialIdentity(prefix: 'spatial-feature', id: 'feature-1'),
    ]);

    expect(() => generator.newId('spatial-link'), throwsA(isA<StateError>()));

    expect(generator.consumedCount, 0);
    expect(generator.remainingCount, 1);
    expect(generator.newId('spatial-feature'), 'feature-1');
  });

  test('rejects calls after scripted identities are exhausted', () {
    final generator = ScriptedSpatialIdentityGenerator([
      const ScriptedSpatialIdentity(
        prefix: 'spatial-revision',
        id: 'revision-1',
      ),
    ]);

    expect(generator.newId('spatial-revision'), 'revision-1');

    expect(
      () => generator.newId('spatial-revision'),
      throwsA(isA<StateError>()),
    );

    expect(generator.consumedCount, 1);
    expect(generator.remainingCount, 0);
  });
}
