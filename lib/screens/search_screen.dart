import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/theme_state.dart';
import 'album_screen.dart';
import 'player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> songs = [];
  List<dynamic> albums = [];
  bool isLoading = true;
  String query = '';

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    _searchController.addListener(() {
      setState(() {
        query = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrary() async {
    try {
      final List<dynamic> results = await Future.wait([fetchSongs(), fetchAlbums()]);
      if (!mounted) return;

      setState(() {
        songs = results[0] as List<dynamic>;
        albums = results[1] as List<dynamic>;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        songs = [];
        albums = [];
        isLoading = false;
      });
    }
  }

  List<dynamic> get _matchingSongs {
    if (query.isEmpty) return <dynamic>[];
    final String needle = query.toLowerCase();

    return songs.where((dynamic song) {
      final String title = _songTitle(song).toLowerCase();
      final String artist = _songArtist(song).toLowerCase();
      return title.contains(needle) || artist.contains(needle);
    }).toList();
  }

  List<dynamic> get _matchingAlbums {
    if (query.isEmpty) return <dynamic>[];
    final String needle = query.toLowerCase();

    return albums.where((dynamic album) {
      final String title = _albumTitle(album).toLowerCase();
      final String artist = _albumArtist(album).toLowerCase();
      return title.contains(needle) || artist.contains(needle);
    }).toList();
  }

  List<_SearchResultItem> get _matchingAll {
    final List<_SearchResultItem> results = [
      ..._matchingAlbums.map((album) {
        return _SearchResultItem.album(album);
      }),
      ..._matchingSongs.map((song) {
        return _SearchResultItem.song(song);
      }),
    ];

    results.sort((a, b) {
      if (a.isAlbum != b.isAlbum) {
        return a.isAlbum ? -1 : 1;
      }
      return a.title.compareTo(b.title);
    });
    return results;
  }

  Future<void> _playSongFromResults(int index, List<dynamic> queue) async {
    final song = queue[index];
    final String songId = _songId(song);
    if (songId.isEmpty) return;

    await playSong(
      getAudioUrl(songId),
      title: _songTitle(song),
      image: getImageUrl(songId),
      artist: _songArtist(song),
      index: index,
      queue: queue,
      trackDuration: durationFromTicks(song['RunTimeTicks']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> matchingSongs = _matchingSongs;
    final List<_SearchResultItem> matchingAll = _matchingAll;
    final bool hasResults = matchingAll.isNotEmpty;
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 168),
          children: [
            Text(
              'Search',
              style: TextStyle(
                color: palette.text,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.9,
                height: 1,
              ),
            ),
            const SizedBox(height: 18),
            _SearchField(controller: _searchController),
            const SizedBox(height: 24),
            if (isLoading && query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: CupertinoActivityIndicator(color: palette.accent),
                ),
              )
            else if (!hasResults)
              _EmptySearchState(query: query)
            else ...[
              ...matchingAll.map((item) {
                final String id = item.id;

                if (item.isAlbum) {
                  return _SearchResultTile(
                    title: item.title,
                    subtitle: 'Album - ${item.subtitle}',
                    imageUrl: id.isEmpty ? '' : getImageUrl(id),
                    fallbackIcon: CupertinoIcons.square_stack_fill,
                    trailingIcon: CupertinoIcons.chevron_forward,
                    resultType: _SearchResultType.album,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AlbumScreen(album: item.value as Map<dynamic, dynamic>),
                        ),
                      );
                    },
                  );
                }

                final int songIndex = matchingSongs.indexOf(item.value);

                return ValueListenableBuilder<int>(
                  valueListenable: currentIndexNotifier,
                  builder: (context, currentIndex, child) {
                    final currentSong = currentIndex >= 0 && currentIndex < globalQueue.length
                        ? globalQueue[currentIndex]
                        : null;
                    final isActive = _songId(currentSong) == id;

                    return ValueListenableBuilder<bool>(
                      valueListenable: isPlayingNotifier,
                      builder: (context, isPlaying, child) {
                        return _SearchResultTile(
                          title: item.title,
                          subtitle: 'Song - ${item.subtitle}',
                          imageUrl: id.isEmpty ? '' : getImageUrl(id),
                          fallbackIcon: CupertinoIcons.music_note,
                          trailingIcon: isActive && isPlaying
                              ? CupertinoIcons.waveform
                              : CupertinoIcons.play_fill,
                          resultType: _SearchResultType.song,
                          isActive: isActive,
                          onTap: () async {
                            if (songIndex == -1) return;
                            final NavigatorState navigator = Navigator.of(context);
                            await _playSongFromResults(
                              songIndex,
                              matchingSongs,
                            );
                            if (!mounted) return;
                            navigator.push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PlayerScreen(
                                  onNext: playNext,
                                  onPrev: playPrev,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: palette.text, fontSize: 15),
      cursorColor: palette.accent,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search songs, albums, artists',
        hintStyle: TextStyle(
          color: palette.mutedText,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          CupertinoIcons.search,
          color: palette.mutedText,
          size: 21,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: palette.mutedText,
                  size: 19,
                ),
                onPressed: controller.clear,
              ),
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.accent.withOpacity(0.35)),
        ),
      ),
    );
  }
}

class _SearchResultItem {
  const _SearchResultItem._({
    required this.value,
    required this.isAlbum,
    required this.id,
    required this.title,
    required this.subtitle,
  });

  factory _SearchResultItem.album(dynamic album) {
    return _SearchResultItem._(
      value: album,
      isAlbum: true,
      id: album is Map ? album['Id']?.toString() ?? '' : '',
      title: _albumTitle(album),
      subtitle: _albumArtist(album),
    );
  }

  factory _SearchResultItem.song(dynamic song) {
    return _SearchResultItem._(
      value: song,
      isAlbum: false,
      id: _songId(song),
      title: _songTitle(song),
      subtitle: _songArtist(song),
    );
  }

  final dynamic value;
  final bool isAlbum;
  final String id;
  final String title;
  final String subtitle;
}

enum _SearchResultType { album, song }

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.trailingIcon,
    required this.resultType,
    required this.onTap,
    this.isActive = false,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final IconData fallbackIcon;
  final IconData trailingIcon;
  final _SearchResultType resultType;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final isAlbum = resultType == _SearchResultType.album;
    final Color baseColor = isAlbum ? palette.surfaceAlt : palette.surface;
    final Color activeColor = palette.surfaceAlt;
    final Color borderColor = isActive ? palette.accent.withOpacity(0.32) : palette.border;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? activeColor : baseColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl.isEmpty
                  ? _ResultArtFallback(icon: fallbackIcon)
                  : Image.network(
                      imageUrl,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _ResultArtFallback(icon: fallbackIcon);
                      },
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 15,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              trailingIcon,
              color: isActive ? palette.accent : palette.mutedText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultArtFallback extends StatelessWidget {
  const _ResultArtFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      width: 54,
      height: 54,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(icon, color: palette.accent, size: 22),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      height: 360,
      alignment: Alignment.center,
      child: Center(
        child: Text(
          query.isEmpty ? 'Search for a song, an album or an artist' : 'No matches for "$query"',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.mutedText,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

String _songId(dynamic song) {
  final id = song is Map ? song['Id'] : null;
  if (id == null) return '';
  return id.toString();
}

String _songTitle(dynamic song) {
  final title = song is Map ? song['Name'] : null;
  return title?.toString() ?? 'Unknown track';
}

String _songArtist(dynamic song) {
  if (song is! Map) return 'Unknown';
  final artists = song['Artists'];
  if (artists is List && artists.isNotEmpty && artists.first != null) {
    return artists.first.toString();
  }
  return 'Unknown';
}

String _albumTitle(dynamic album) {
  final title = album is Map ? album['Name'] : null;
  return title?.toString() ?? 'Unknown album';
}

String _albumArtist(dynamic album) {
  if (album is! Map) return 'Unknown artist';

  final albumArtist = album['AlbumArtist'];
  if (albumArtist != null && albumArtist.toString().isNotEmpty) {
    return albumArtist.toString();
  }

  final artists = album['Artists'];
  if (artists is List && artists.isNotEmpty && artists.first != null) {
    return artists.first.toString();
  }

  return 'Unknown artist';
}
