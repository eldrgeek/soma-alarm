import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sidekick/src/dee_stream/dispatch_input_client.dart';
import 'package:sidekick/src/dee_stream/relay_resolver.dart';

class _FakeResolver extends RelayResolver {
  final String url;
  _FakeResolver(this.url) : super(userUrl: url, candidates: const []);
  @override
  Future<String> resolve() async => url;
  @override
  String? get cached => url;
}

void main() {
  group('DispatchInputClient', () {
    test('rejects empty token without hitting network', () async {
      final mock = MockClient((req) async {
        fail('Should not have called the network: ${req.url}');
      });
      final client = DispatchInputClient(
        resolver: _FakeResolver('http://test:3333'),
        tokenGetter: () => '',
        client: mock,
      );
      final r = await client.send('hello');
      expect(r.ok, false);
      expect(r.error, contains('token'));
    });

    test('rejects empty body without hitting network', () async {
      final mock = MockClient((req) async {
        fail('Should not have called the network');
      });
      final client = DispatchInputClient(
        resolver: _FakeResolver('http://test:3333'),
        tokenGetter: () => 'tok',
        client: mock,
      );
      final r = await client.send('   ');
      expect(r.ok, false);
      expect(r.error, contains('Empty'));
    });

    test('happy path: 200 with queued:true returns ok+timestamp', () async {
      late http.Request capturedReq;
      final mock = MockClient((req) async {
        capturedReq = req;
        return http.Response(
          jsonEncode({'ok': true, 'queued': true, 'timestamp': '2026-05-06T20:00:00Z'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = DispatchInputClient(
        resolver: _FakeResolver('http://test:3333'),
        tokenGetter: () => 'sekrit',
        client: mock,
      );
      final r = await client.send('hi dee', source: 'pulse');
      expect(r.ok, true);
      expect(r.timestamp, '2026-05-06T20:00:00Z');
      expect(capturedReq.url.toString(), 'http://test:3333/dispatch_input');
      expect(capturedReq.method, 'POST');
      expect(capturedReq.headers['x-dispatch-token'], 'sekrit');
      final body = jsonDecode(capturedReq.body) as Map<String, dynamic>;
      expect(body['message'], 'hi dee');
      expect(body['source'], 'pulse');
    });

    test('401 surfaces a friendly message', () async {
      final mock = MockClient((req) async => http.Response('{"error":"Bad token"}', 401));
      final client = DispatchInputClient(
        resolver: _FakeResolver('http://test:3333'),
        tokenGetter: () => 'wrong',
        client: mock,
      );
      final r = await client.send('hi');
      expect(r.ok, false);
      expect(r.statusCode, 401);
      expect(r.error, contains('token'));
    });

    test('413 surfaces oversize message', () async {
      final mock = MockClient((req) async => http.Response('{"error":"too large"}', 413));
      final client = DispatchInputClient(
        resolver: _FakeResolver('http://test:3333'),
        tokenGetter: () => 'tok',
        client: mock,
      );
      final r = await client.send('hi');
      expect(r.ok, false);
      expect(r.statusCode, 413);
      expect(r.error, contains('too large'));
    });

    test('local oversize check trips before network', () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        return http.Response('', 200);
      });
      final client = DispatchInputClient(
        resolver: _FakeResolver('http://test:3333'),
        tokenGetter: () => 'tok',
        client: mock,
      );
      final r = await client.send('x' * 9000);
      expect(r.ok, false);
      expect(r.error, contains('8000'));
      expect(calls, 0);
    });
  });
}
