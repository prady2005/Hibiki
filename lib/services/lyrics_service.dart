import 'dart:convert';
import 'package:http/http.dart' as http;

final Map<String, List<Map<String, dynamic>>> _lyricsMemoryCache =
    <String, List<Map<String, dynamic>>>{};

const Map<String, String> _lyricsHeaders = <String, String>{
  'User-Agent': 'MusicApp/1.0 (lyrics lookup)',
};

Future<List<Map<String, dynamic>>> fetchLyrics(String title, String artist) async {
  final String cleanTitle = _cleanTitle(title);
  final String cleanArtist = _cleanArtist(artist);
  final cacheKey = '${_normalize(cleanArtist)}-${_normalize(cleanTitle)}';
  if (_lyricsMemoryCache.containsKey(cacheKey)) {
    return _lyricsMemoryCache[cacheKey]!;
  }

  try {
    for (final Future<List<Map<String, dynamic>>> Function() lookup in _lyricLookups(
      cleanTitle,
      cleanArtist,
    )) {
      final List<Map<String, dynamic>> lyrics = await lookup().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      if (lyrics.isNotEmpty) {
        _lyricsMemoryCache[cacheKey] = lyrics;
        return lyrics;
      }
    }
  } catch (e) {
    print('Lyrics fetch error: $e');
  }

  return [];
}

List<Future<List<Map<String, dynamic>>> Function()> _lyricLookups(
  String title,
  String artist,
) {
  final String normalizedArtist = _normalize(artist);
  final String titleOnly = _stripFeaturedArtists(title);
  final List<String> artistParts = _artistParts(artist);
  final String primaryArtist = artistParts.isEmpty ? artist : artistParts.first;

  return <Future<List<Map<String, dynamic>>> Function()>[
    () => _fetchExactLyrics(title, artist),
    if (primaryArtist.isNotEmpty && _normalize(primaryArtist) != normalizedArtist)
      () => _fetchExactLyrics(title, primaryArtist),
    () => _fetchExactLyrics(title, ''),
    if (titleOnly != title) () => _fetchExactLyrics(titleOnly, artist),
    if (titleOnly != title && primaryArtist.isNotEmpty)
      () => _fetchExactLyrics(titleOnly, primaryArtist),
    () => _fetchSearchLyrics(title, artist),
    if (primaryArtist.isNotEmpty && _normalize(primaryArtist) != normalizedArtist)
      () => _fetchSearchLyrics(title, primaryArtist),
    if (titleOnly != title) () => _fetchSearchLyrics(titleOnly, artist),
    if (titleOnly != title && primaryArtist.isNotEmpty)
      () => _fetchSearchLyrics(titleOnly, primaryArtist),
    () => _fetchSearchLyrics(title, ''),
    if (titleOnly != title) () => _fetchSearchLyrics(titleOnly, ''),
  ];
}

Future<List<Map<String, dynamic>>> _fetchSearchLyrics(String title, String artist) async {
  if (title.isEmpty) return [];

  final String query = Uri.encodeComponent(
    artist.isEmpty || artist == 'Unknown' ? title : '$artist $title',
  );
  final Uri url = Uri.parse('https://lrclib.net/api/search?q=$query');
  final http.Response res =
      await http.get(url, headers: _lyricsHeaders).timeout(const Duration(seconds: 8));

  if (res.statusCode != 200) return [];

  final data = jsonDecode(res.body) as List<dynamic>;
  final Map<dynamic, dynamic>? bestMatch = _bestSyncedMatch(data, title, artist);
  final syncedLyrics = bestMatch?['syncedLyrics'];
  if (syncedLyrics is String && syncedLyrics.trim().isNotEmpty) {
    return parseLRC(syncedLyrics);
  }
  return [];
}

Future<List<Map<String, dynamic>>> _fetchExactLyrics(String title, String artist) async {
  if (title.isEmpty) return [];

  final url = Uri.https('lrclib.net', '/api/get', <String, String>{
    'track_name': title,
    if (artist.isNotEmpty && artist != 'Unknown') 'artist_name': artist,
  });

  final http.Response res =
      await http.get(url, headers: _lyricsHeaders).timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) return [];

  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final syncedLyrics = data['syncedLyrics'];
  if (syncedLyrics is String && syncedLyrics.trim().isNotEmpty) {
    return parseLRC(syncedLyrics);
  }
  return [];
}

Map<dynamic, dynamic>? _bestSyncedMatch(
  List<dynamic> matches,
  String title,
  String artist,
) {
  final String normalizedTitle = _normalize(title);
  final String normalizedArtist = _normalize(artist);

  final List<Map<dynamic, dynamic>> syncedMatches = matches.whereType<Map<dynamic, dynamic>>().where((match) {
    final syncedLyrics = match['syncedLyrics'];
    return syncedLyrics is String && syncedLyrics.trim().isNotEmpty;
  }).toList();
  if (syncedMatches.isEmpty) return null;

  syncedMatches.sort((a, b) {
    return _matchScore(b, normalizedTitle, normalizedArtist)
        .compareTo(_matchScore(a, normalizedTitle, normalizedArtist));
  });

  return syncedMatches.first;
}

int _matchScore(Map<dynamic, dynamic> match, String title, String artist) {
  final String trackName = _normalize(match['trackName']?.toString() ?? '');
  final String artistName = _normalize(match['artistName']?.toString() ?? '');
  var score = 0;

  if (trackName == title) score += 8;
  if (trackName.contains(title) || title.contains(trackName)) score += 3;
  if (artist.isNotEmpty && artistName == artist) score += 5;
  if (artist.isNotEmpty && (artistName.contains(artist) || artist.contains(artistName))) {
    score += 2;
  }

  return score;
}

List<Map<String, dynamic>> parseLRC(String lrc) {
  final List<String> lines = lrc.split('\n');

  return lines.expand((line) {
    final List<RegExpMatch> matches = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]').allMatches(line).toList();
    if (matches.isEmpty) return <Map<String, dynamic>>[];

    final String text = line.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    if (text.isEmpty) return <Map<String, dynamic>>[];

    return matches.map((match) {
      final int min = int.parse(match.group(1)!);
      final double sec = double.parse(match.group(2)!);

      return <String, dynamic>{
        'time': Duration(
          minutes: min,
          milliseconds: (sec * 1000).round(),
        ),
        'text': text,
      };
    });
  }).toList()
    ..sort((a, b) => (a['time'] as Duration).compareTo(b['time'] as Duration));
}

String _cleanTitle(String title) {
  return title
      .replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ')
      .replaceAll(RegExp(r'\s*\[.*?\]\s*'), ' ')
      .replaceAll(RegExp(r'\s+-\s+.*$'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripFeaturedArtists(String title) {
  return title
      .replaceAll(RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _cleanArtist(String artist) {
  return artist.replaceAll('ï¿½', ' ').replaceAll('�', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> _artistParts(String artist) {
  return _cleanArtist(artist)
      .split(RegExp(r'\s*(?:,|;|/|&|\+|\band\b)\s*', caseSensitive: false))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && part != 'Unknown')
      .toList();
}

String _normalize(String value) {
  return _cleanTitle(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
