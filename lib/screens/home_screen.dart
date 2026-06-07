import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/library_state.dart';
import '../services/theme_state.dart';
import '../widgets/app_feedback.dart';
import 'album_screen.dart';
import 'player_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> albums = [];
  List<dynamic> songs = [];
  String selectedFilter = 'All';
  String selectedFavoriteType = 'Songs';
  bool isServerOnline = false;
  bool isSongsLoading = true;

  @override
  void initState() {
    super.initState();
    loadAlbums();
    loadSongs();
    favoriteAlbumIdsNotifier.addListener(_refreshHome);
    favoriteSongIdsNotifier.addListener(_refreshHome);
    playlistsNotifier.addListener(_refreshHome);
    recentItemsNotifier.addListener(_refreshHome);
  }

  @override
  void dispose() {
    favoriteAlbumIdsNotifier.removeListener(_refreshHome);
    favoriteSongIdsNotifier.removeListener(_refreshHome);
    playlistsNotifier.removeListener(_refreshHome);
    recentItemsNotifier.removeListener(_refreshHome);
    super.dispose();
  }

  void _refreshHome() {
    if (mounted) setState(() {});
  }

  Future<void> loadAlbums() async {
    try {
      final List<dynamic> data = await fetchAlbums();
      if (!mounted) return;

      setState(() {
        albums = data;
        isServerOnline = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        albums = [];
        isServerOnline = false;
      });
    }
  }

  Future<void> loadSongs() async {
    try {
      final List<dynamic> data = await fetchSongs();
      if (!mounted) return;

      setState(() {
        songs = data;
        isSongsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        songs = [];
        isSongsLoading = false;
      });
    }
  }

  String getGreeting() {
    final int hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  List<dynamic> get filteredAlbums {
    if (selectedFilter == 'Favourites') {
      return albums.where(isAlbumFavorite).toList();
    }
    return albums;
  }

  List<dynamic> get favoriteSongs {
    return songs.where(isSongFavorite).toList()
      ..sort((a, b) => sortTitle(a).compareTo(sortTitle(b)));
  }

  Future<void> _showCreatePlaylistSheet() async {
    if (songs.isEmpty) return;
    final AppThemePalette palette = activeAppPalette(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _CreatePlaylistSheet(
        songs: List<dynamic>.from(songs),
        albums: List<dynamic>.from(albums),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> visibleAlbums = filteredAlbums;
    final List<RecentLibraryItem> recentItems = recentItemsNotifier.value;
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 168),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          getGreeting(),
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      _ServerStatusIndicator(isOnline: isServerOnline),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Home',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.9,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final filter in const [
                        'All',
                        'Recent',
                        'Favourites',
                      ])
                        _HomeFilterChip(
                          label: filter,
                          selected: selectedFilter == filter,
                          onTap: () {
                            setState(() {
                              selectedFilter = filter;
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (selectedFilter == 'All') ...[
                    _PlaylistPanel(
                      isLoadingSongs: isSongsLoading,
                      onCreatePlaylist: _showCreatePlaylistSheet,
                    ),
                    const SizedBox(height: 28),
                  ],
                  if (selectedFilter == 'Recent') ...[
                    Text(
                      'Recently played',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (recentItems.isEmpty)
                      const _HomeEmptyState(message: 'No recent plays yet')
                    else
                      ...recentItems.map((item) {
                        return _RecentItemTile(
                          item: item,
                          onTap: () async {
                            if (item.isAlbum) {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => AlbumScreen(album: item.source),
                                ),
                              );
                              return;
                            }

                            if (item.isPlaylist) {
                              if (item.playlistSongs.isEmpty) return;

                              final firstSong = item.playlistSongs.first;
                              final String id = _songId(firstSong);
                              if (id.isEmpty) return;

                              final NavigatorState navigator = Navigator.of(context);
                              await playSong(
                                getAudioUrl(id),
                                title: _songTitle(firstSong),
                                image: getImageUrl(id),
                                artist: _songArtist(firstSong),
                                index: 0,
                                queue: item.playlistSongs,
                                trackDuration: durationFromTicks(
                                  firstSong['RunTimeTicks'],
                                ),
                                playbackSourceType: 'Playlist',
                                playbackSourceName: item.title,
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
                              return;
                            }

                            final int songIndex = songs.indexWhere((song) {
                              return _songId(song) == item.id;
                            });
                            if (songIndex == -1) return;

                            final NavigatorState navigator = Navigator.of(context);
                            await playSong(
                              getAudioUrl(item.id),
                              title: item.title,
                              image: getImageUrl(item.imageId),
                              artist: item.subtitle,
                              index: songIndex,
                              queue: songs,
                              trackDuration: durationFromTicks(
                                songs[songIndex]['RunTimeTicks'],
                              ),
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
                      }),
                  ] else if (selectedFilter == 'Favourites') ...[
                    Text(
                      'Favourites',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          for (final type in const ['Songs', 'Albums'])
                            Expanded(
                              child: _FavoriteTabButton(
                                label: type,
                                selected: selectedFavoriteType == type,
                                onTap: () {
                                  setState(() {
                                    selectedFavoriteType = type;
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (selectedFavoriteType == 'Songs') ...[
                      if (favoriteSongs.isEmpty)
                        const _HomeEmptyState(message: 'No favourite songs yet')
                      else
                        ...List.generate(favoriteSongs.length, (index) {
                          final song = favoriteSongs[index];
                          final String id = _songId(song);

                          return _FavoriteSongTile(
                            title: _songTitle(song),
                            artist: _songArtist(song),
                            imageUrl: id.isEmpty ? '' : getImageUrl(id),
                            onTap: () async {
                              final NavigatorState navigator = Navigator.of(context);
                              await playSong(
                                getAudioUrl(id),
                                title: _songTitle(song),
                                image: id.isEmpty ? '' : getImageUrl(id),
                                artist: _songArtist(song),
                                index: index,
                                queue: favoriteSongs,
                                trackDuration: durationFromTicks(song['RunTimeTicks']),
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
                        }),
                    ] else if (visibleAlbums.isEmpty)
                      const _HomeEmptyState(message: 'No favourite albums yet')
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visibleAlbums.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                        itemBuilder: (context, index) {
                          final album = visibleAlbums[index];
                          final String id = album['Id']?.toString() ?? '';
                          final String title = album['Name']?.toString() ?? '';
                          final String artist = _albumArtist(album);
                          final String imageUrl = id.isEmpty ? '' : getImageUrl(id);
                          final trackCount = album['ChildCount'];

                          return _SongCard(
                            title: title,
                            artist: artist,
                            imageUrl: imageUrl,
                            accentLabel: trackCount is int ? '$trackCount tracks' : 'Album',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      AlbumScreen(album: album as Map<dynamic, dynamic>),
                                ),
                              );
                            },
                          );
                        },
                      ),
                  ] else ...[
                    Text(
                      'Albums',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (visibleAlbums.isEmpty)
                      const _HomeEmptyState(message: 'No albums yet')
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visibleAlbums.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                        itemBuilder: (context, index) {
                          final album = visibleAlbums[index];
                          final String id = album['Id']?.toString() ?? '';
                          final String title = album['Name']?.toString() ?? '';
                          final String artist = _albumArtist(album);
                          final String imageUrl = id.isEmpty ? '' : getImageUrl(id);
                          final trackCount = album['ChildCount'];

                          return _SongCard(
                            title: title,
                            artist: artist,
                            imageUrl: imageUrl,
                            accentLabel: trackCount is int ? '$trackCount tracks' : 'Album',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      AlbumScreen(album: album as Map<dynamic, dynamic>),
                                ),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

String _songId(dynamic song) {
  final id = song is Map ? song['Id'] : null;
  return id?.toString() ?? '';
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

String _albumId(dynamic album) {
  return album is Map ? album['Id']?.toString() ?? '' : '';
}

String _albumTitle(dynamic album) {
  final title = album is Map ? album['Name'] : null;
  return title?.toString() ?? 'Unknown album';
}

class _HomeFilterChip extends StatelessWidget {
  const _HomeFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? palette.accent : palette.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.accent : palette.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FavoriteTabButton extends StatelessWidget {
  const _FavoriteTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

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

class _FavoriteSongTile extends StatelessWidget {
  const _FavoriteSongTile({
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.onTap,
  });

  final String title;
  final String artist;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl.isEmpty
                  ? const _FavouriteSongArtFallback()
                  : Image.network(
                      imageUrl,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const _FavouriteSongArtFallback();
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
                    artist,
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
            Icon(
              CupertinoIcons.play_fill,
              color: palette.accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _FavouriteSongArtFallback extends StatelessWidget {
  const _FavouriteSongArtFallback();

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      width: 54,
      height: 54,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.music_note,
        color: palette.accent,
        size: 22,
      ),
    );
  }
}

class _CreatePlaylistSheet extends StatefulWidget {
  const _CreatePlaylistSheet({
    required this.songs,
    required this.albums,
  });

  final List<dynamic> songs;
  final List<dynamic> albums;

  @override
  State<_CreatePlaylistSheet> createState() => _CreatePlaylistSheetState();
}

class _CreatePlaylistSheetState extends State<_CreatePlaylistSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedSongIds = <String>{};
  final Map<String, List<dynamic>> _albumSongCache = <String, List<dynamic>>{};
  final Set<String> _loadingAlbumIds = <String>{};
  String _query = '';
  bool _showNameError = false;

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _defaultPlaylistName => nextUntitledPlaylistName();

  Set<String> get _albumIds {
    return widget.albums.map(_albumId).where((String id) => id.isNotEmpty).toSet();
  }

  List<dynamic> get _standaloneSongs {
    final Set<String> albumIds = _albumIds;
    return widget.songs.where((song) {
      return !belongsToAnyAlbum(song, albumIds);
    }).toList()
      ..sort((a, b) => sortTitle(a).compareTo(sortTitle(b)));
  }

  List<dynamic> get _sortedAlbums {
    return List<dynamic>.from(widget.albums)..sort((a, b) => sortTitle(a).compareTo(sortTitle(b)));
  }

  List<dynamic> get _visibleSongs {
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return _standaloneSongs;

    return widget.songs.where((song) {
      return _songTitle(song).toLowerCase().contains(needle);
    }).toList()
      ..sort((a, b) => sortTitle(a).compareTo(sortTitle(b)));
  }

  Future<void> _toggleAlbum(dynamic album) async {
    final String albumId = _albumId(album);
    if (albumId.isEmpty) return;

    if (!_albumSongCache.containsKey(albumId)) {
      setState(() {
        _loadingAlbumIds.add(albumId);
      });
      try {
        final List<dynamic> albumSongs = await fetchAlbumSongs(albumId);
        if (!mounted) return;
        _albumSongCache[albumId] = albumSongs;
      } finally {
        if (mounted) {
          setState(() {
            _loadingAlbumIds.remove(albumId);
          });
        }
      }
    }

    final List<String> songIds = (_albumSongCache[albumId] ?? <dynamic>[])
        .map(_songId)
        .where((id) => id.isNotEmpty)
        .toList();
    if (songIds.isEmpty) return;

    final bool allSelected = songIds.every(_selectedSongIds.contains);
    setState(() {
      if (allSelected) {
        _selectedSongIds.removeAll(songIds);
      } else {
        _selectedSongIds.addAll(songIds);
      }
    });
  }

  void _createPlaylist() {
    final List<dynamic> selectedSongs = widget.songs.where((song) {
      return _selectedSongIds.contains(_songId(song));
    }).toList();
    if (selectedSongs.isEmpty) return;

    final String typedName = _nameController.text.trim();
    final String playlistName = typedName.isEmpty ? _defaultPlaylistName : typedName;
    addPlaylist(playlistName, selectedSongs);
    showAppFeedback(context, '$playlistName playlist created');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final List<dynamic> visibleAlbums = _query.trim().isEmpty ? _sortedAlbums : <dynamic>[];
    final List<dynamic> visibleSongs = _visibleSongs;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Create playlist',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(CupertinoIcons.xmark, color: palette.text),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PlaylistTextField(
              controller: _nameController,
              hintText: _defaultPlaylistName,
              textCapitalization: TextCapitalization.sentences,
              hasError: _showNameError,
              helperText: _showNameError ? 'Add a name or use the grey default name.' : null,
              onChanged: (value) {
                if (_showNameError && value.trim().isNotEmpty) {
                  setState(() {
                    _showNameError = false;
                  });
                }
              },
            ),
            const SizedBox(height: 14),
            _PlaylistTextField(
              controller: _searchController,
              hintText: 'Search songs',
              textCapitalization: TextCapitalization.sentences,
              prefixIcon: CupertinoIcons.search,
              suffixIcon: _query.isEmpty ? null : CupertinoIcons.xmark_circle_fill,
              onSuffixTap: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                });
              },
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
            const SizedBox(height: 14),
            Expanded(
              child: visibleSongs.isEmpty && visibleAlbums.isEmpty
                  ? Center(
                      child: Text(
                        _query.trim().isEmpty ? 'No songs or albums found' : 'No songs found',
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: visibleAlbums.length + visibleSongs.length,
                      itemBuilder: (context, index) {
                        if (index < visibleAlbums.length) {
                          final album = visibleAlbums[index];
                          final String albumId = _albumId(album);
                          final bool isLoadingAlbum = _loadingAlbumIds.contains(albumId);
                          final List<dynamic>? albumSongs = _albumSongCache[albumId];
                          final bool selected = albumSongs != null &&
                              albumSongs.isNotEmpty &&
                              albumSongs
                                  .map(_songId)
                                  .where((id) => id.isNotEmpty)
                                  .every(_selectedSongIds.contains);

                          return _PlaylistSongOption(
                            title: _albumTitle(album),
                            artist: isLoadingAlbum ? 'Loading album songs...' : 'Album',
                            icon: CupertinoIcons.square_stack_fill,
                            selected: selected,
                            onTap: () => _toggleAlbum(album),
                          );
                        }

                        final int songIndex = index - visibleAlbums.length;
                        final song = visibleSongs[songIndex];
                        final String id = _songId(song);
                        final bool selected = _selectedSongIds.contains(id);

                        return _PlaylistSongOption(
                          title: _songTitle(song),
                          artist: _songArtist(song),
                          icon: CupertinoIcons.music_note,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedSongIds.remove(id);
                              } else if (id.isNotEmpty) {
                                _selectedSongIds.add(id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: readableTextOn(palette.accent),
                  disabledBackgroundColor: palette.surfaceAlt,
                  disabledForegroundColor: palette.mutedText,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _selectedSongIds.isEmpty ? null : _createPlaylist,
                child: Text(
                  _selectedSongIds.isEmpty
                      ? 'Select songs'
                      : 'Create with ${_selectedSongIds.length} songs',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTextField extends StatelessWidget {
  const _PlaylistTextField({
    required this.controller,
    required this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.onChanged,
    this.hasError = false,
    this.helperText,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final String? helperText;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    const errorColor = Color(0xFFFF9F0A);

    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      style: TextStyle(color: palette.text),
      cursorColor: palette.accent,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: palette.mutedText.withOpacity(0.85)),
        helperText: helperText,
        helperStyle: const TextStyle(color: errorColor),
        prefixIcon:
            prefixIcon == null ? null : Icon(prefixIcon, color: palette.mutedText, size: 20),
        suffixIcon: suffixIcon == null
            ? null
            : IconButton(
                onPressed: onSuffixTap,
                icon: Icon(
                  suffixIcon,
                  color: palette.mutedText,
                  size: 18,
                ),
              ),
        filled: true,
        fillColor: palette.surfaceAlt.withOpacity(0.7),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: hasError ? errorColor : palette.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: hasError ? errorColor : palette.accent.withOpacity(0.55),
          ),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _ServerStatusIndicator extends StatelessWidget {
  const _ServerStatusIndicator({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final statusColor = isOnline ? const Color(0xFF34C759) : const Color(0xFFFF453A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.circle_fill, size: 10, color: statusColor),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: palette.border,
        ),
      ),
      child: Center(
        child: Text(
          message,
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

class _RecentItemTile extends StatelessWidget {
  const _RecentItemTile({required this.item, required this.onTap});

  final RecentLibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final bool isAlbum = item.isAlbum;
    final bool isPlaylist = item.isPlaylist;
    final IconData fallbackIcon = isAlbum
        ? CupertinoIcons.square_stack_fill
        : isPlaylist
            ? CupertinoIcons.music_albums_fill
            : CupertinoIcons.music_note;
    final itemType = isAlbum
        ? 'Album'
        : isPlaylist
            ? 'Playlist'
            : 'Song';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isAlbum ? palette.surfaceAlt : palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.imageId.isEmpty
                  ? _RecentArtFallback(
                      icon: fallbackIcon,
                    )
                  : Image.network(
                      getImageUrl(item.imageId),
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _RecentArtFallback(
                          icon: fallbackIcon,
                        );
                      },
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
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
                    '$itemType - ${item.subtitle}',
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
            Icon(
              CupertinoIcons.chevron_forward,
              color: palette.accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentArtFallback extends StatelessWidget {
  const _RecentArtFallback({required this.icon});

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

class _PlaylistPanel extends StatelessWidget {
  const _PlaylistPanel({
    required this.isLoadingSongs,
    required this.onCreatePlaylist,
  });

  final bool isLoadingSongs;
  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Create playlist',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.background,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: isLoadingSongs ? null : onCreatePlaylist,
                icon: const Icon(CupertinoIcons.add, size: 17),
                label: const Text('Create'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isLoadingSongs ? 'Loading songs...' : 'Build a playlist from your music library.',
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistSongOption extends StatelessWidget {
  const _PlaylistSongOption({
    required this.title,
    required this.artist,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String artist;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? palette.surfaceAlt : palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? palette.accent.withOpacity(0.3) : palette.border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? CupertinoIcons.check_mark_circled_solid : icon,
              color: selected ? palette.accent : palette.mutedText,
              size: 22,
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.accentLabel,
    required this.onTap,
  });

  final String title;
  final String artist;
  final String imageUrl;
  final String accentLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl.isEmpty)
                        _CardArtFallback()
                      else
                        Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _CardArtFallback();
                          },
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.08),
                              Colors.transparent,
                              Colors.black.withOpacity(0.28),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.14),
                            ),
                          ),
                          child: Text(
                            accentLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.46),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardArtFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF232323),
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.music_note,
        color: Colors.white.withOpacity(0.7),
        size: 28,
      ),
    );
  }
}
