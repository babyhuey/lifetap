import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves a commander card name to an image URL used as a zone background.
abstract class CommanderArtSource {
  Future<String?> artUrl(String commanderName);
}

/// Looks art up via Scryfall's fuzzy named-card endpoint. Returns null (never
/// throws) on any failure — non-200, missing image, malformed JSON, or a
/// network error — so the UI can fall back to the player's solid color.
///
/// Resolved URLs are cached in [SharedPreferences] keyed by the normalized
/// commander name. Commander art URLs are stable, so a name seen once resolves
/// instantly on later lookups and keeps working with no network.
class ScryfallArtSource implements CommanderArtSource {
  ScryfallArtSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// SharedPreferences key prefix for cached name→URL entries.
  static const _cachePrefix = 'cmdrart:';

  @override
  Future<String?> artUrl(String commanderName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cachePrefix${commanderName.trim().toLowerCase()}';
    final cached = prefs.getString(key);
    if (cached != null) return cached;

    final url = await _fetch(commanderName);
    if (url != null) await prefs.setString(key, url);
    return url;
  }

  Future<String?> _fetch(String commanderName) async {
    final uri = Uri.https('api.scryfall.com', '/cards/named', {
      'fuzzy': commanderName,
    });
    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              // Scryfall asks callers to identify themselves and request JSON.
              'User-Agent': 'LifeTap2/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final images = decoded['image_uris'];
      if (images is! Map) return null;
      final artCrop = images['art_crop'];
      if (artCrop is String) return artCrop;
      final normal = images['normal'];
      if (normal is String) return normal;
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Overridable in tests/UI with a fake source so no test hits the network.
final commanderArtSourceProvider = Provider<CommanderArtSource>(
  (ref) => ScryfallArtSource(),
);
