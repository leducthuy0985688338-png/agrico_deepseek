import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agrico_deepseek/core/approval/firebase_approval_authority.dart';

void main() {
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
