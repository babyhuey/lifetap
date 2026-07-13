import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetap/data/commander_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a [ScryfallArtSource] backed by a [MockClient] that always returns
/// [response], capturing the request URI/headers it was called with.
({ScryfallArtSource source, List<http.Request> requests}) _stubbed(
  http.Response Function(http.Request request) response,
) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return response(request);
  });
  return (source: ScryfallArtSource(client: client), requests: requests);
}

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Start every test with an empty, headless prefs store so the name→URL cache
  // begins cold (cache miss → the fetch path runs exactly as before).
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ScryfallArtSource', () {
    test('returns image_uris.art_crop on a 200 with images', () async {
      final stub = _stubbed(
        (_) => _json({
          'image_uris': {
            'art_crop': 'https://img/art_crop.jpg',
            'normal': 'https://img/normal.jpg',
          },
        }, 200),
      );

      expect(await stub.source.artUrl('Atraxa'), 'https://img/art_crop.jpg');
    });

    test('falls back to image_uris.normal when art_crop is absent', () async {
      final stub = _stubbed(
        (_) => _json({
          'image_uris': {'normal': 'https://img/normal.jpg'},
        }, 200),
      );

      expect(await stub.source.artUrl('Atraxa'), 'https://img/normal.jpg');
    });

    test('returns null on a 404', () async {
      final stub = _stubbed((_) => _json({'object': 'error'}, 404));

      expect(await stub.source.artUrl('Nonexistent Card'), isNull);
    });

    test('returns null on malformed JSON', () async {
      final stub = _stubbed((_) => http.Response('not json {', 200));

      expect(await stub.source.artUrl('Atraxa'), isNull);
    });

    test('returns null when the request throws (network error)', () async {
      final client = MockClient((_) => throw http.ClientException('offline'));
      final source = ScryfallArtSource(client: client);

      expect(await source.artUrl('Atraxa'), isNull);
    });

    test('URL-encodes the commander name into the fuzzy query', () async {
      final stub = _stubbed((_) => _json({'image_uris': {}}, 200));

      await stub.source.artUrl("Atraxa, Praetors' Voice");

      final uri = stub.requests.single.url;
      expect(uri.host, 'api.scryfall.com');
      expect(uri.path, '/cards/named');
      // Decoded round-trip proves the value was encoded on the wire...
      expect(uri.queryParameters['fuzzy'], "Atraxa, Praetors' Voice");
      // ...and the raw query carries no literal space or comma.
      expect(uri.query, isNot(contains(' ')));
      expect(uri.query, contains('%2C'));
    });

    test('sends Scryfall-etiquette headers', () async {
      final stub = _stubbed((_) => _json({'image_uris': {}}, 200));

      await stub.source.artUrl('Atraxa');

      final headers = stub.requests.single.headers;
      expect(headers['user-agent'], 'LifeTap2/1.0');
      expect(headers['accept'], contains('application/json'));
    });
  });

  group('persistent name→URL cache', () {
    test(
      'a resolved name is cached; a second lookup makes no HTTP request',
      () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          if (calls > 1) throw http.ClientException('must not fetch twice');
          return _json({
            'image_uris': {'art_crop': 'https://img/art_crop.jpg'},
          }, 200);
        });
        final source = ScryfallArtSource(client: client);

        expect(await source.artUrl('Atraxa'), 'https://img/art_crop.jpg');
        expect(await source.artUrl('Atraxa'), 'https://img/art_crop.jpg');
        expect(calls, 1, reason: 'the second lookup must be served from cache');
      },
    );

    test(
      'the cache is keyed by the normalized name (trim + lowercase)',
      () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return _json({
            'image_uris': {'art_crop': 'https://img/art_crop.jpg'},
          }, 200);
        });
        final source = ScryfallArtSource(client: client);

        expect(await source.artUrl('Atraxa'), 'https://img/art_crop.jpg');
        expect(await source.artUrl('  ATRAXA  '), 'https://img/art_crop.jpg');
        expect(
          calls,
          1,
          reason: 'differing case/whitespace hit the same entry',
        );
      },
    );

    test(
      'a previously-cached name still resolves when the client is offline',
      () async {
        // Prime the cache with one successful fetch.
        final online = ScryfallArtSource(
          client: MockClient(
            (_) async => _json({
              'image_uris': {'art_crop': 'https://img/art_crop.jpg'},
            }, 200),
          ),
        );
        expect(await online.artUrl('Atraxa'), 'https://img/art_crop.jpg');

        // A fresh source whose client always throws still returns the cached URL.
        final offline = ScryfallArtSource(
          client: MockClient((_) => throw http.ClientException('offline')),
        );
        expect(await offline.artUrl('Atraxa'), 'https://img/art_crop.jpg');
      },
    );

    test('a null result is never cached (a later success is stored)', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        // First lookup 404s (null, not cached); the second succeeds.
        if (calls == 1) return _json({'object': 'error'}, 404);
        return _json({
          'image_uris': {'art_crop': 'https://img/art_crop.jpg'},
        }, 200);
      });
      final source = ScryfallArtSource(client: client);

      expect(await source.artUrl('Atraxa'), isNull);
      expect(await source.artUrl('Atraxa'), 'https://img/art_crop.jpg');
      expect(
        calls,
        2,
        reason: 'the null miss must not short-circuit the retry',
      );
    });
  });
}
