import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifetap/data/commander_art.dart';

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
}
