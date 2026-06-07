import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/library_state.dart';
import '../services/theme_state.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<dynamic> songs = [];
  List<dynamic> albums = [];
  bool isLoading = true;
  String selectedTab = 'Songs';

  @override
  void initState() {
    super.initState();
    _loadLibrary();
    playlistsNotifier.addListener(_refreshLibrary);
  }

  @override
  void dispose() {
    playlistsNotifier.removeListener(_refreshLibrary);
    super.dispose();
  }

  void _refreshLibrary() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLibrary() async {
    try {
      final List<dynamic> results = await Future.wait([fetchSongs(), fetchAlbums()]);
      if (!mounted) return;
      final sortedAlbums = List<dynamic>.from(results[1] as Iterable<dynamic>)
        ..sort((dynamic a, dynamic b) => _albumTitle(a).toLowerCase().compareTo(_albumTitle(b).toLowerCase()));
      final Set<String> albumIds =
          sortedAlbums.map(_albumId).where((String id) => id.isNotEmpty).toSet();
      final List<dynamic> standaloneSongs = (results[0] as List<dynamic>)
          .where((dynamic song) => !belongsToAnyAlbum(song, albumIds))
          .toList()
        ..sort((dynamic a, dynamic b) => _songTitle(a).toLowerCase().compareTo(_songTitle(b).toLowerCase()));

      setState(() {
        songs = standaloneSongs;
        albums = sortedAlbums;
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

  Future<void> _playSong(int index) async {
    final song = songs[index];
    final String id = _songId(song);
    if (id.isEmpty) return;

    await playSong(
      getAudioUrl(id),
      title: _songTitle(song),
      image: getImageUrl(id),
      artist: _songArtist(song),
      index: index,
      queue: songs,
      trackDuration: durationFromTicks(song['RunTimeTicks']),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<AppPlaylist> playlists = playlistsNotifier.value;
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 168),
          children: [
            Text(
              'Library',
              style: TextStyle(
                color: palette.text,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.9,
                height: 1,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _LibraryStat(
                    icon: CupertinoIcons.music_note_2,
                    value: '${songs.length}',
                    label: 'Songs',
                    palette: palette,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LibraryStat(
                    icon: CupertinoIcons.square_stack_fill,
                    value: '${albums.length}',
                    label: 'Albums',
                    palette: palette,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LibraryStat(
                    icon: CupertinoIcons.music_albums_fill,
                    value: '${playlists.length}',
                    label: 'Playlists',
                    palette: palette,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  for (final tab in const ['Songs', 'Albums', 'Playlists'])
                    Expanded(
                      child: _LibraryTabButton(
                        label: tab,
                        selected: selectedTab == tab,
                        palette: palette,
                        onTap: () => setState(() => selectedTab = tab),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Center(
                  child: CupertinoActivityIndicator(color: palette.accent),
                ),
              )
            else if (selectedTab == 'Songs')
              ...List.generate(songs.length, (index) {
                final song = songs[index];
                final String id = _songId(song);
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
                        return _LibraryTile(
                          title: _songTitle(song),
                          subtitle: _songArtist(song),
                          imageUrl: id.isEmpty ? '' : getImageUrl(id),
                          fallbackIcon: CupertinoIcons.music_note,
                          trailingIcon: isActive && isPlaying
                              ? CupertinoIcons.waveform
                              : CupertinoIcons.play_fill,
                          isActive: isActive,
                          palette: palette,
                          onTap: () async {
                            if (isActive) {
                              togglePlayPause();
                              return;
                            }
                            await _playSong(index);
                          },
                        );
                      },
                    );
                  },
                );
              })
            else if (selectedTab == 'Albums')
              ...albums.map((album) {
                final String id = _albumId(album);
                return _LibraryTile(
                  title: _albumTitle(album),
                  subtitle: _albumArtist(album),
                  imageUrl: id.isEmpty ? '' : getImageUrl(id),
                  fallbackIcon: CupertinoIcons.square_stack_fill,
                  trailingIcon: CupertinoIcons.chevron_forward,
                  palette: palette,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AlbumScreen(album: album as Map<dynamic, dynamic>),
                      ),
                    );
                  },
                );
              })
            else if (playlists.isEmpty)
              _LibraryEmptyState(message: 'No playlists yet', palette: palette)
            else
              ...playlists.map((playlist) {
                return _LibraryTile(
                  title: playlist.name,
                  subtitle: '${playlist.songCount} songs',
                  imageUrl: '',
                  fallbackIcon: CupertinoIcons.music_albums_fill,
                  trailingIcon: CupertinoIcons.chevron_forward,
                  palette: palette,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PlaylistScreen(playlist: playlist),
                      ),
                    );
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _LibraryStat extends StatelessWidget {
  const _LibraryStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String value;
  final String label;
  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.accent, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.text,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTabButton extends StatelessWidget {
  const _LibraryTabButton({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.background : palette.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.trailingIcon,
    required this.onTap,
    required this.palette,
    this.isActive = false,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final IconData fallbackIcon;
  final IconData trailingIcon;
  final VoidCallback onTap;
  final AppThemePalette palette;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? palette.surfaceAlt : palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isActive ? palette.accent.withOpacity(0.28) : palette.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl.isEmpty
                  ? _ArtFallback(icon: fallbackIcon, palette: palette)
                  : Image.network(
                      imageUrl,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _ArtFallback(icon: fallbackIcon, palette: palette);
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
                      fontWeight: FontWeight.w600,
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
            Icon(trailingIcon, color: palette.accent, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.message, required this.palette});

  final String message;
  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      alignment: Alignment.center,
      child: Text(
        message,
        style: TextStyle(
          color: palette.mutedText,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ArtFallback extends StatelessWidget {
  const _ArtFallback({required this.icon, required this.palette});

  final IconData icon;
  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(icon, color: palette.accent, size: 22),
    );
  }
}

String _songId(dynamic song) => song is Map ? song['Id']?.toString() ?? '' : '';

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

String _albumId(dynamic album) {
  return album is Map ? album['Id']?.toString() ?? '' : '';
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
