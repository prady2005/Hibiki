import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/library_state.dart';
import '../services/theme_state.dart';
import '../widgets/app_feedback.dart';
import '../widgets/mini_player.dart';
import 'player_screen.dart';

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.album});

  final Map<dynamic, dynamic> album;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<dynamic> songs = [];
  bool isLoading = true;
  late final ValueNotifier<LoopMode> repeatModeNotifier;
  late final VoidCallback _repeatModeListener;

  @override
  void initState() {
    super.initState();
    repeatModeNotifier = ValueNotifier<LoopMode>(queueRepeatModeNotifier.value);
    _repeatModeListener = () {
      repeatModeNotifier.value = queueRepeatModeNotifier.value;
    };
    queueRepeatModeNotifier.addListener(_repeatModeListener);
    _loadAlbumSongs();
  }

  @override
  void dispose() {
    queueRepeatModeNotifier.removeListener(_repeatModeListener);
    repeatModeNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadAlbumSongs() async {
    try {
      final String albumId = _albumId;
      if (albumId.isEmpty) return;

      final List<dynamic> data = await fetchAlbumSongs(albumId);
      final List<dynamic> enrichedData = data.map((song) {
        if (song is! Map) return song;

        return <dynamic, dynamic>{
          ...song,
          'AlbumId': song['AlbumId'] ?? albumId,
          'Album': song['Album'] ?? _albumTitle,
          'AlbumArtist': song['AlbumArtist'] ?? _albumArtist,
          '_PlayedFromAlbum': true,
        };
      }).toList();
      if (!mounted) return;

      setState(() {
        songs = enrichedData;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        songs = [];
        isLoading = false;
      });
    }
  }

  String get _albumId => widget.album['Id']?.toString() ?? '';
  String get _albumTitle => widget.album['Name']?.toString() ?? 'Unknown album';

  String get _albumArtist {
    final artist = widget.album['AlbumArtist'];
    if (artist != null && artist.toString().isNotEmpty) {
      return artist.toString();
    }

    final artists = widget.album['Artists'];
    if (artists is List && artists.isNotEmpty && artists.first != null) {
      return artists.first.toString();
    }

    return 'Unknown artist';
  }

  Future<void> _playFromIndex(int index, {bool shuffle = false}) async {
    if (songs.isEmpty) return;

    await setShuffleEnabled(shuffle);
    final song = songs[index];
    final String songId = _songId(song);
    if (songId.isEmpty) return;

    await playSong(
      getAudioUrl(songId),
      title: _songTitle(song),
      image: getImageUrl(songId),
      artist: _songArtist(song),
      index: index,
      queue: songs,
      trackDuration: durationFromTicks(song['RunTimeTicks']),
      playbackSourceType: 'Album',
      playbackSourceName: _albumTitle,
    );
  }

  Future<void> _toggleRepeat() async {
    final LoopMode current = repeatModeNotifier.value;
    final LoopMode next = current == LoopMode.off
        ? LoopMode.all
        : current == LoopMode.all
            ? LoopMode.one
            : LoopMode.off;
    await setQueueRepeatMode(next);
  }

  Future<void> _toggleShuffle() async {
    await setShuffleEnabled(!player.shuffleModeEnabled);
  }

  Future<void> _openPlayerAfterPlay(Future<void> Function() playAction) async {
    final NavigatorState navigator = Navigator.of(context);
    await playAction();
    if (!mounted) return;
    _openPlayer(navigator);
  }

  void _openPlayer([NavigatorState? navigator]) {
    (navigator ?? Navigator.of(context)).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlayerScreen(
          onNext: playNext,
          onPrev: playPrev,
        ),
      ),
    );
  }

  bool _isActiveAlbumQueue() {
    if (songs.isEmpty) return false;
    if (currentPlaybackSourceTypeNotifier.value != 'Album') return false;
    if (currentPlaybackSourceNameNotifier.value != _albumTitle) return false;
    if (currentIndexNotifier.value < 0) return false;
    if (globalQueue.length != songs.length) return false;

    for (var index = 0; index < songs.length; index++) {
      if (_songId(globalQueue[index]) != _songId(songs[index])) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final String imageUrl = _albumId.isEmpty ? '' : getImageUrl(_albumId);
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: palette.border),
                          ),
                          child: Icon(
                            CupertinoIcons.chevron_back,
                            color: palette.accent,
                            size: 20,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<Set<String>>(
                        valueListenable: favoriteAlbumIdsNotifier,
                        builder: (context, _, child) {
                          final bool isFavorite = isAlbumFavorite(widget.album);

                          return GestureDetector(
                            onTap: () {
                              final bool wasFavorite = isAlbumFavorite(widget.album);
                              toggleFavoriteAlbum(widget.album);
                              showAppFeedback(
                                context,
                                wasFavorite
                                    ? 'Removed from favourite albums'
                                    : 'Added to favourite albums',
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isFavorite
                                    ? const Color(0xFFFF453A).withOpacity(0.16)
                                    : palette.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isFavorite
                                      ? const Color(0xFFFF453A).withOpacity(0.42)
                                      : palette.border,
                                ),
                              ),
                              child: Icon(
                                isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                                color: isFavorite ? const Color(0xFFFF453A) : palette.accent,
                                size: 21,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: imageUrl.isEmpty
                              ? const _AlbumArtFallback(size: 220)
                              : Image.network(
                                  imageUrl,
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const _AlbumArtFallback(size: 220);
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _albumTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _albumArtist,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: ListenableBuilder(
                              listenable: Listenable.merge([
                                currentIndexNotifier,
                                queueRevisionNotifier,
                                currentPlaybackSourceTypeNotifier,
                                currentPlaybackSourceNameNotifier,
                                isPlayingNotifier,
                              ]),
                              builder: (context, child) {
                                final bool isThisAlbumActive = _isActiveAlbumQueue();
                                final bool isAudioPlaying =
                                    isThisAlbumActive && isPlayingNotifier.value;

                                return FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: palette.accent,
                                    foregroundColor: palette.background,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  onPressed: songs.isEmpty
                                      ? null
                                      : () {
                                          if (isThisAlbumActive) {
                                            togglePlayPause();
                                          } else {
                                            _openPlayerAfterPlay(() => _playFromIndex(0));
                                          }
                                        },
                                  icon: Icon(
                                    isAudioPlaying
                                        ? CupertinoIcons.pause_fill
                                        : CupertinoIcons.play_fill,
                                    size: 17,
                                  ),
                                  label: Text(isThisAlbumActive ? 'Playing' : 'Play'),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          StreamBuilder<bool>(
                            stream: player.shuffleModeEnabledStream,
                            initialData: player.shuffleModeEnabled,
                            builder: (context, snapshot) {
                              final bool isShuffleOn = snapshot.data ?? false;
                              return _ControlChipButton(
                                icon: CupertinoIcons.shuffle,
                                label: 'Shuffle',
                                isActive: isShuffleOn,
                                onTap: songs.isEmpty ? null : _toggleShuffle,
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          ValueListenableBuilder<LoopMode>(
                            valueListenable: repeatModeNotifier,
                            builder: (context, loopMode, child) {
                              return _ControlChipButton(
                                icon: loopMode == LoopMode.one
                                    ? CupertinoIcons.repeat_1
                                    : CupertinoIcons.repeat,
                                label: loopMode == LoopMode.off
                                    ? 'Repeat'
                                    : loopMode == LoopMode.one
                                        ? 'One'
                                        : 'All',
                                isActive: loopMode != LoopMode.off,
                                onTap: _toggleRepeat,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (isLoading)
                        Center(
                          child: CupertinoActivityIndicator(
                            color: palette.accent,
                          ),
                        )
                      else if (songs.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: palette.border,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.music_note_list,
                                color: palette.accent,
                                size: 26,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No songs found',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...List.generate(songs.length, (index) {
                          final song = songs[index];
                          final String title = _songTitle(song);
                          final String artist = _songArtist(song);

                          return ValueListenableBuilder<int>(
                            valueListenable: currentIndexNotifier,
                            builder: (context, currentIndex, child) {
                              final currentSong =
                                  currentIndex >= 0 && currentIndex < globalQueue.length
                                      ? globalQueue[currentIndex]
                                      : null;
                              final bool isActive =
                                  currentIndex == index && _songId(currentSong) == _songId(song);

                              return ValueListenableBuilder<bool>(
                                valueListenable: isPlayingNotifier,
                                builder: (context, isPlaying, child) {
                                  return _AlbumSongTile(
                                    index: index,
                                    title: title,
                                    artist: artist,
                                    isActive: isActive,
                                    isPlaying: isPlaying,
                                    onTap: () => _openPlayerAfterPlay(
                                      () => _playFromIndex(index),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: AppMiniPlayer(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumArtFallback extends StatelessWidget {
  const _AlbumArtFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      width: size,
      height: size,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.music_note,
        color: palette.accent,
        size: size * 0.16,
      ),
    );
  }
}

class _ControlChipButton extends StatelessWidget {
  const _ControlChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final Color activeForeground = readableTextOn(palette.accent);

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: isActive ? palette.accent : palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isActive ? activeForeground : palette.accent,
                size: 17,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? activeForeground : palette.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumSongTile extends StatelessWidget {
  const _AlbumSongTile({
    required this.index,
    required this.title,
    required this.artist,
    required this.isActive,
    required this.isPlaying,
    required this.onTap,
  });

  final int index;
  final String title;
  final String artist;
  final bool isActive;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: isActive ? palette.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive ? palette.accent.withOpacity(0.28) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: isActive ? palette.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 22,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? palette.accent : palette.mutedText,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                ),
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
            const SizedBox(width: 12),
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: isActive && isPlaying
                    ? const _NowPlayingBars()
                    : Icon(
                        isActive ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                        color: isActive ? palette.accent : palette.mutedText,
                        size: 18,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingBars extends StatefulWidget {
  const _NowPlayingBars();

  @override
  State<_NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<_NowPlayingBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 18,
          height: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final double phase = (_controller.value + (index * 0.22)) * math.pi * 2;
              final double height = 5 + (math.sin(phase).abs() * 12);

              return Padding(
                padding: EdgeInsets.only(right: index == 2 ? 0 : 3),
                child: Container(
                  width: 3,
                  height: height,
                  decoration: BoxDecoration(
                    color: activeAppPalette(context).accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
        );
      },
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
