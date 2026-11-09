import 'dart:convert';
import 'dart:io';
import 'package:agrico_deepseek/core/approval/approval_policy.dart';
import 'package:agrico_deepseek/core/permissions/authorization.dart';
import 'package:agrico_deepseek/core/periods/period_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agrico_deepseek/core/approval/firebase_approval_authority.dart';

void main() {
  test(
    'unknown activation outcome retries through current authenticated proof without duplicate mutation',
    () async {
      final p = DocumentApprovalPolicy(
        farm: 'f',
        kind: ApprovalKind.machineRun,
        currency: 'VND',
        version: 1,
        selfEnabled: false,
        createPermission: 'machine.log',
        approvePermission: 'machine.verify',
        changedBy: 'manager',
        independentLimit: '100',
      );
      final digest = PeriodLock.digest(p.toJson());
      var posted = false, writes = 0;
      final actor = AuthorizationSubject(
        userId: 'activator',
        farmId: 'f',
        membershipId: 'activator',
        permissionCodes: const {'approval.policy.activate'},
        dataScopes: const {DataScope.allFarm},
      );
      final record = {
        'policy': p.toJson(),
        'digest': digest,
        'version': 1,
        'authorityRevision': 1,
        'proposedBy': 'manager',
        'proposedAt': '2026-11-01T00:00:00Z',
      };
      final authority = FirebaseApprovalAuthority(
        userId: () => 'activator',
        idToken: () async => 'synthetic',
        endpoint: (_) => Uri.parse('https://example.invalid/call'),
        client: MockClient((request) async {
          final data = (jsonDecode(request.body) as Map)['data'] as Map;
          if (data['operation'] == 'activate') {
            writes++;
            posted = true;
            throw const SocketException('response lost');
          }
          return http.Response(
            jsonEncode({
              'result': {
                'farm': 'f',
                'kind': 'machineRun',
                'currency': 'VND',
                'authorityRevision': 1,
                'head': {'version': 1, 'digest': digest},
                'expectedActive': posted
                    ? {'version': 1, 'digest': digest}
                    : null,
                'drafts': posted ? [] : [record],
                'active': posted
                    ? {
                        ...record,
                        'activatedBy': 'activator',
                        'activatedAt': '2026-11-01T00:01:00Z',
                        'reference': 'server-current-proof',
                      }
                    : null,
              },
            }),
            200,
          );
        }),
      );
      await expectLater(
        authority.activateCatalog(actor, p, digest, 0),
        throwsA(isA<SocketException>()),
      );
      expect(
        await authority.activateCatalog(actor, p, digest, 0),
        'server-current-proof',
      );
      expect(writes, 1);
    },
  );

  test(
    'real catalog transport forwards genuine author and CAS active/head/revision',
    () async {
      final p = DocumentApprovalPolicy(
        farm: 'f',
        kind: ApprovalKind.machineRun,
        currency: 'VND',
        version: 1,
        selfEnabled: false,
        createPermission: 'machine.log',
        approvePermission: 'machine.verify',
        changedBy: 'manager',
        independentLimit: '100',
      );
      final digest = PeriodLock.digest(p.toJson());
      var calls = 0;
      final actor = AuthorizationSubject(
        userId: 'activator',
        farmId: 'f',
        membershipId: 'activator',
        permissionCodes: const {'approval.policy.activate'},
        dataScopes: const {DataScope.allFarm},
      );
      final authority = FirebaseApprovalAuthority(
        userId: () => 'activator',
        idToken: () async => 'synthetic',
        endpoint: (_) => Uri.parse('https://example.invalid/call'),
        client: MockClient((request) async {
          final data = (jsonDecode(request.body) as Map)['data'] as Map;
          calls++;
          if (data['operation'] == 'listDrafts') {
            expect(data['farm'], 'f');
            return http.Response(
              jsonEncode({
                'result': {
                  'farm': 'f',
                  'kind': 'machineRun',
                  'currency': 'VND',
                  'authorityRevision': 3,
                  'head': {'version': 1, 'digest': digest},
                  'expectedActive': null,
                  'drafts': [
                    {
                      'policy': p.toJson(),
                      'digest': digest,
                      'version': 1,
                      'authorityRevision': 3,
                      'proposedBy': 'manager',
                      'proposedAt': '2026-11-01T00:00:00Z',
                    },
                  ],
                  'active': null,
                },
              }),
              200,
            );
          }
          expect(data['operation'], 'activate');
          expect(data['expectedActive'], isNull);
          expect(data['expectedDraftHead'], {'version': 1, 'digest': digest});
          expect(data['expectedAuthorityRevision'], 3);
          expect((data['policy'] as Map)['changedBy'], 'manager');
          return http.Response('{"result":{"reference":"reference"}}', 200);
        }),
      );
      expect(await authority.activateCatalog(actor, p, digest, 0), 'reference');
      expect(calls, 2);
    },
  );

  test(
    'logout/login same UID during response is rejected by session epoch',
    () async {
      var epoch = 1;
      final authority = FirebaseApprovalAuthority(
        userId: () => 'same',
        sessionEpoch: () => epoch,
        idToken: () async => 'synthetic',
        endpoint: (_) => Uri.parse('https://example.invalid/call'),
        client: MockClient((_) async {
          epoch++;
          return http.Response('{"result":{"current":true}}', 200);
        }),
      );
      await expectLater(
        authority.call('companyApprovalAuthority', {'operation': 'verify'}),
        throwsStateError,
      );
    },
  );

  test(
    'callable uses authenticated token and protocol without authority cache',
    () async {
      var calls = 0;
      final authority = FirebaseApprovalAuthority(
        userId: () => 'manager',
        idToken: () async => 'synthetic-token',
        endpoint: (name) => Uri.parse('https://example.invalid/$name'),
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/companyApprovalAuthority');
          expect(request.headers['Authorization'], 'Bearer synthetic-token');
          expect(jsonDecode(request.body), {
            'data': {'operation': 'verify'},
          });
          return http.Response(
            jsonEncode({
              'result': {'current': calls == 1},
            }),
            200,
          );
        }),
      );
      expect(
        (await authority.call('companyApprovalAuthority', {
          'operation': 'verify',
        }))['current'],
        isTrue,
      );
      expect(
        (await authority.call('companyApprovalAuthority', {
          'operation': 'verify',
        }))['current'],
        isFalse,
      );
      expect(calls, 2);
    },
  );
  test(
    'account changed while request awaits response discards authority result',
    () async {
      String? user = 'manager';
      final authority = FirebaseApprovalAuthority(
        userId: () => user,
        idToken: () async => 'synthetic-token',
        endpoint: (name) => Uri.parse('https://example.invalid/$name'),
        client: MockClient((request) async {
          user = 'other';
          return http.Response('{"result":{"current":true}}', 200);
        }),
      );
      await expectLater(
        authority.call('companyApprovalAuthority', {}),
        throwsStateError,
      );
    },
  );
  test('logout during token refresh never sends authority request', () async {
    String? user = 'manager';
    var calls = 0;
    final authority = FirebaseApprovalAuthority(
      userId: () => user,
      idToken: () async {
        user = null;
        return 'synthetic-token';
      },
      endpoint: (name) => Uri.parse('https://example.invalid/$name'),
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      authority.call('companyApprovalAuthority', {}),
      throwsStateError,
    );
    expect(calls, 0);
  });
  for (final response in [
    http.Response('{"error":{"status":"PERMISSION_DENIED"}}', 403),
    http.Response('{"result":[]}', 200),
    http.Response('invalid', 200),
  ]) {
    test(
      'denied or malformed authority response fails closed ${response.statusCode}/${response.body}',
      () async {
        final authority = FirebaseApprovalAuthority(
          userId: () => 'manager',
          idToken: () async => 'synthetic-token',
          endpoint: (name) => Uri.parse('https://example.invalid/$name'),
          client: MockClient((_) async => response),
        );
        await expectLater(
          authority.call('companyApprovalAuthority', {}),
          throwsA(anything),
        );
        expect(await authority.beneficiaryUsers('f', 'party'), isNull);
      },
    );
  }
  test('verified external party differs from unresolved party', () async {
    final authority = FirebaseApprovalAuthority(
      userId: () => 'manager',
      idToken: () async => 'synthetic-token',
      endpoint: (name) => Uri.parse('https://example.invalid/$name'),
      client: MockClient(
        (_) async =>
            http.Response('{"result":{"verified":true,"users":[]}}', 200),
      ),
    );
    expect(await authority.beneficiaryUsers('f', 'external'), isEmpty);
  });
}
