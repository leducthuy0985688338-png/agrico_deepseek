import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agrico_deepseek/features/company_workspace/application/workspace_service.dart';
import 'package:agrico_deepseek/features/company_workspace/data/firebase_workspace_transport.dart';
import 'package:agrico_deepseek/features/company_workspace/data/workspace_command_channel.dart';

class Channel implements WorkspaceCommandChannel {
  final submitted = <String>[];
  Json response = {
    'status': 'accepted',
    'result': {'records': []},
  };
  Object? failure;
  void Function()? duringRead;
  int reads = 0;
  @override
  Future<void> submit(String f, String u, String op, Json c) async {
    submitted.add(op);
  }

  @override
  Future<Json> result(String f, String u, String op, Json c) async {
    reads++;
    duringRead?.call();
    if (failure != null) throw failure!;
    return response;
  }
}

void main() {
  const command = {
    'action': 'message.list',
    'entityId': 'room',
    'expectedRevision': 0,
    'payload': <String, dynamic>{},
  };
  FirebaseWorkspaceTransport transport(
    Channel channel, {
    void Function(String)? session,
  }) => FirebaseWorkspaceTransport(
    channel: channel,
    verifySession: session ?? (_) {},
    wait: (_) async {},
  );
  test(
    'transport returns current result and retries same operation after network uncertainty',
    () async {
      final channel = Channel()..failure = http.ClientException('offline');
      final t = transport(channel);
      await expectLater(
        t.send('farm', 'worker', 'stable', command),
        throwsA(isA<http.ClientException>()),
      );
      channel.failure = null;
      expect((await t.send('farm', 'worker', 'stable', command))['result'], {
        'records': [],
      });
      expect(channel.submitted, ['stable', 'stable']);
    },
  );
  test(
    'transport never returns private response after account switch',
    () async {
      var uid = 'worker';
      final channel = Channel()..duringRead = () => uid = 'other';
      final t = transport(
        channel,
        session: (expected) {
          if (uid != expected) throw const WorkspaceFailure('session');
        },
      );
      await expectLater(
        t.send('farm', 'worker', 'one', command),
        throwsA(
          isA<WorkspaceFailure>().having((e) => e.code, 'code', 'session'),
        ),
      );
    },
  );
  test('pending polls are bounded and keep the same operation id', () async {
    final channel = Channel()..response = {'status': 'pending'};
    await expectLater(
      transport(channel).send('farm', 'worker', 'one', command),
      throwsA(isA<WorkspaceFailure>().having((e) => e.code, 'code', 'pending')),
    );
    expect(channel.reads, 12);
    expect(channel.submitted, ['one']);
  });
  test('technical stale acknowledgement contains no private record', () async {
    final channel = Channel()
      ..response = {
        'status': 'accepted',
        'result': {},
        'resultUnavailable': true,
      };
    expect(
      (await transport(
        channel,
      ).send('farm', 'worker', 'one', command))['result'],
      isEmpty,
    );
  });
  test('only a recorded command rejection is WorkspaceRejected', () async {
    final channel = Channel()
      ..response = {'status': 'rejected', 'error': 'conflict'};
    await expectLater(
      transport(channel).send('farm', 'worker', 'one', command),
      throwsA(isA<WorkspaceRejected>()),
    );
  });
  test(
    'callable protocol sends bearer token and command, receives only released result',
    () async {
      final reader = WorkspaceResultClient(
        endpoint: Uri.parse('http://localhost/result'),
        idToken: () async => 'test-token',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {
            'data': {'farm': 'farm', 'operation': 'one', 'command': command},
          });
          return http.Response(
            jsonEncode({
              'result': {
                'status': 'accepted',
                'result': {'unchanged': true, 'token': 'v1'},
              },
            }),
            200,
          );
        }),
      );
      expect((await reader.read('farm', 'one', command))['result'], {
        'unchanged': true,
        'token': 'v1',
      });
    },
  );
  test('callable authorization denial is not a business rejection', () async {
    final reader = WorkspaceResultClient(
      endpoint: Uri.parse('http://localhost/result'),
      idToken: () async => 'test-token',
      client: MockClient(
        (_) async =>
            http.Response('{"error":{"status":"PERMISSION_DENIED"}}', 403),
      ),
    );
    try {
      await reader.read('farm', 'one', command);
      fail('must deny');
    } on WorkspaceFailure catch (e) {
      expect(e.code, 'denied');
      expect(e, isNot(isA<WorkspaceRejected>()));
    }
  });
  test('logged out callable reader sends no network request', () async {
    var calls = 0;
    final reader = WorkspaceResultClient(
      endpoint: Uri.parse('http://localhost/result'),
      idToken: () async => null,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      reader.read('farm', 'one', command),
      throwsA(isA<WorkspaceFailure>()),
    );
    expect(calls, 0);
  });
}
