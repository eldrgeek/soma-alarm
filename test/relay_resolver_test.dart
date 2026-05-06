import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;

import 'package:sidekick/src/dee_stream/relay_resolver.dart';

http.Client _stubClient(Map<String, int> hostToStatus) {
  return MockClient((req) async {
    final origin = '${req.url.scheme}://${req.url.host}:${req.url.port}';
    final status = hostToStatus[origin];
    if (status == null) {
      throw http.ClientException(
          "Failed host lookup: '${req.url.host}'", req.url);
    }
    if (status == 200) {
      return http.Response('{"jobs":[]}', 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('err', status);
  });
}

void main() {
  group('RelayResolver', () {
    test('user URL wins when reachable', () async {
      final r = RelayResolver(
        userUrl: 'http://user-host:3333',
        candidates: const ['http://192.168.4.36:3333'],
        client: _stubClient({
          'http://user-host:3333': 200,
          'http://192.168.4.36:3333': 200,
        }),
      );
      expect(await r.resolve(), 'http://user-host:3333');
      expect(r.cached, 'http://user-host:3333');
    });

    test('falls through to first reachable candidate when user URL fails',
        () async {
      final r = RelayResolver(
        userUrl: 'http://mikes-mac:3333',
        candidates: const [
          'http://192.168.4.36:3333',
          'http://mikes-mac.local:3333',
        ],
        client: _stubClient({
          'http://192.168.4.36:3333': 200,
        }),
      );
      expect(await r.resolve(), 'http://192.168.4.36:3333');
      expect(r.lastErrors.containsKey('http://mikes-mac:3333'), isTrue);
    });

    test('throws RelayResolverException with per-attempt errors when all fail',
        () async {
      final r = RelayResolver(
        userUrl: 'http://mikes-mac:3333',
        candidates: const ['http://192.168.4.36:3333'],
        client: _stubClient(const {}),
      );
      try {
        await r.resolve();
        fail('expected exception');
      } catch (e) {
        expect(e, isA<RelayResolverException>());
        final ex = e as RelayResolverException;
        expect(ex.attemptErrors.length, 2);
        expect(ex.toString(), contains('mikes-mac'));
      }
    });

    test('empty user URL is skipped, candidates still tried', () async {
      final r = RelayResolver(
        userUrl: '',
        candidates: const ['http://192.168.4.36:3333'],
        client: _stubClient({'http://192.168.4.36:3333': 200}),
      );
      expect(await r.resolve(), 'http://192.168.4.36:3333');
    });

    test('reset() clears the cache so next resolve re-probes', () async {
      var calls = 0;
      final c = MockClient((req) async {
        calls++;
        return http.Response('{"jobs":[]}', 200);
      });
      final r = RelayResolver(
        userUrl: 'http://user-host:3333',
        candidates: const [],
        client: c,
      );
      await r.resolve();
      await r.resolve();
      expect(calls, 1, reason: 'second resolve should hit cache');
      r.reset();
      await r.resolve();
      expect(calls, 2);
    });

    test('probeOne returns null on success, error string on failure',
        () async {
      final r = RelayResolver(
        userUrl: '',
        candidates: const [],
        client: _stubClient({'http://good:3333': 200}),
      );
      expect(await r.probeOne('http://good:3333'), isNull);
      final err = await r.probeOne('http://bad:3333');
      expect(err, isNotNull);
      expect(err, contains('bad'));
    });
  });
}
