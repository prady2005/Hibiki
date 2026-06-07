import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/library_activity_log.dart';
import '../services/library_state.dart';
import '../services/theme_state.dart';
import '../widgets/app_feedback.dart';
import '../widgets/mini_player.dart';
import '../widgets/playlist_edit_sheet.dart';
import 'player_screen.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlist});

  final AppPlaylist playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final ValueNotifier<LoopMode> repeatModeNotifier;
  late final VoidCallback _repeatModeListener;
  bool _isRemovingSongs = false;
  final Set<String> _selectedSongIds = <String>{};

  @override
  void initState() {
    super.initState();
    repeatModeNotifier = ValueNotifier<LoopMode>(queueRepeatModeNotifier.value);
    _repeatModeListener = () {
      repeatModeNotifier.value = queueRepeatModeNotifier.value;
    };
    queueRepeatModeNotifier.addListener(_repeatModeListener);
  }

  @override
  void dispose() {
    queueRepeatModeNotifier.removeListener(_repeatModeListener);
    repeatModeNotifier.dispose();
    super.dispose();
  }

  AppPlaylist get _playlist {
    return findPlaylistById(widget.playlist.id) ?? widget.playlist;
  }

  Future<void> _playFromIndex(int index, {bool shuffle = false}) async {
    final AppPlaylist playlist = _playlist;
    if (playlist.songs.isEmpty) return;

    await setShuffleEnabled(shuffle);
    final song = playlist.songs[index];
    final String songId = _songId(song);
    if (songId.isEmpty) return;

    await playSong(
      getAudioUrl(songId),
      title: _songTitle(song),
      image: getImageUrl(songId),
      artist: _songArtist(song),
      index: index,
      queue: playlist.songs,
      trackDuration: durationFromTicks(song['RunTimeTicks']),
      playbackSourceType: 'Playlist',
      playbackSourceName: playlist.name,
    );
    recordRecentPlaylist(playlist);
  }

  void _showEditPlaylistSheet() {
    final AppPlaylist playlist = _playlist;
    if (playlist.songs.isEmpty) {
      showAppFeedback(context, 'Add songs to this playlist first');
      return;
    }

    final AppThemePalette palette = activeAppPalette(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => PlaylistEditSheet(
        playlist: playlist,
        onSave: (updated) {
          replacePlaylist(updated);
          syncQueueWithPlaylistSongs(updated.songs, updated.name);
          logPlaylistReordered(updated.name);
          if (!mounted) return;
          setState(() {});
          showAppFeedback(context, 'Playlist updated');
        },
      ),
    );
  }

  void _toggleRemovalMode() {
    setState(() {
      _isRemovingSongs = !_isRemovingSongs;
      _selectedSongIds.clear();
    });
  }

  void _toggleSongSelection(String songId) {
    if (songId.isEmpty) return;
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  Future<void> _removeSelectedSongs() async {
    if (_selectedSongIds.isEmpty) return;

    final AppPlaylist playlist = _playlist;
    final int removeCount = _selectedSongIds.length;
    final bool? shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) {
        final AppThemePalette palette = activeAppPalette(context);
        return AlertDialog(
          backgroundColor: palette.surface,
          title: Text(
            'Remove songs?',
            style: TextStyle(color: palette.text),
          ),
          content: Text(
            removeCount == 1
                ? 'Remove 1 song from "${playlist.name}"?'
                : 'Remove $removeCount songs from "${playlist.name}"?',
            style: TextStyle(color: palette.mutedText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Remove',
                style: TextStyle(color: Color(0xFFFF453A)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true || !mounted) return;

    final bool removed = removeSongsFromPlaylist(playlist.id, _selectedSongIds);
    if (!removed) return;

    final AppPlaylist? updated = findPlaylistById(playlist.id);
    if (updated != null) {
      syncQueueWithPlaylistSongs(updated.songs, updated.name);
    }

    if (!mounted) return;
    setState(() {
      _isRemovingSongs = false;
      _selectedSongIds.clear();
    });
    showAppFeedback(
      context,
      removeCount == 1 ? 'Removed 1 song' : 'Removed $removeCount songs',
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

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return ValueListenableBuilder<List<AppPlaylist>>(
      valueListenable: playlistsNotifier,
      builder: (context, _, child) {
        final AppPlaylist playlist = _playlist;

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
                          _IconShellButton(
                            icon: CupertinoIcons.chevron_back,
                            onTap: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          if (_isRemovingSongs) ...[
                            _IconShellButton(
                              icon: CupertinoIcons.checkmark,
                              onTap: _toggleRemovalMode,
                            ),
                            const SizedBox(width: 8),
                          ] else ...[
                            _IconShellButton(
                              icon: CupertinoIcons.pencil,
                              onTap: playlist.songs.isEmpty ? null : _showEditPlaylistSheet,
                            ),
                            const SizedBox(width: 8),
                            _IconShellButton(
                              icon: CupertinoIcons.minus_circle,
                              color: const Color(0xFFFF453A),
                              onTap: playlist.songs.isEmpty ? null : _toggleRemovalMode,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _IconShellButton(
                            icon: CupertinoIcons.delete,
                            color: const Color(0xFFFF453A),
                            onTap: () => _confirmDeletePlaylist(context),
                          ),
                        ],
                      ),
                    ),
                    if (_isRemovingSongs) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Select songs to remove',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(20, 22, 20, _isRemovingSongs ? 168 : 112),
                        children: [
                      Center(
                        child: Container(
                          width: 176,
                          height: 176,
                          decoration: BoxDecoration(
                            color: palette.surfaceAlt,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: palette.border),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            CupertinoIcons.music_albums_fill,
                            color: palette.accent,
                            size: 56,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        playlist.name,
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
                        '${playlist.songCount} songs',
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
                                final bool isThisPlaylistActive = _isActivePlaylistQueue();
                                final bool isAudioPlaying =
                                    isThisPlaylistActive && isPlayingNotifier.value;

                                return FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: palette.accent,
                                    foregroundColor: palette.background,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  onPressed: playlist.songs.isEmpty
                                      ? null
                                      : () {
                                          if (isThisPlaylistActive) {
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
                                  label: Text(isThisPlaylistActive ? 'Playing' : 'Play'),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          _ControlChipButton(
                            icon: CupertinoIcons.shuffle,
                            label: 'Shuffle',
                            onTap: playlist.songs.isEmpty
                                ? null
                                : () => _openPlayerAfterPlay(
                                      () => _playFromIndex(0, shuffle: true),
                                    ),
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
                      if (playlist.songs.isEmpty)
                        const _PlaylistEmptyState()
                      else
                        ...List.generate(playlist.songs.length, (index) {
                          final song = playlist.songs[index];
                          final String songId = _songId(song);
                          return ValueListenableBuilder<int>(
                            valueListenable: currentIndexNotifier,
                            builder: (context, currentIndex, child) {
                              final currentSong =
                                  currentIndex >= 0 && currentIndex < globalQueue.length
                                      ? globalQueue[currentIndex]
                                      : null;
                              final bool isActive = !_isRemovingSongs &&
                                  currentIndex == index &&
                                  _songId(currentSong) == songId;

                              return ValueListenableBuilder<bool>(
                                valueListenable: isPlayingNotifier,
                                builder: (context, isPlaying, child) {
                                  return _PlaylistSongTile(
                                    index: index,
                                    title: _songTitle(song),
                                    artist: _songArtist(song),
                                    isActive: isActive,
                                    isPlaying: isPlaying,
                                    selectionMode: _isRemovingSongs,
                                    isSelected: _selectedSongIds.contains(songId),
                                    onTap: _isRemovingSongs
                                        ? () => _toggleSongSelection(songId)
                                        : () => _openPlayerAfterPlay(
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
                if (_isRemovingSongs && _selectedSongIds.isNotEmpty)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 88,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF453A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _removeSelectedSongs,
                      child: Text(
                        _selectedSongIds.length == 1
                            ? 'Remove 1 song'
                            : 'Remove ${_selectedSongIds.length} songs',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: AppMiniPlayer(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletePlaylist(BuildContext context) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: activeAppPalette(context).surface,
          title: Text(
            'Delete playlist?',
            style: TextStyle(color: activeAppPalette(context).text),
          ),
          content: Text(
            'This removes "${widget.playlist.name}" from your library.',
            style: TextStyle(color: activeAppPalette(context).mutedText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF453A)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !context.mounted) return;
    final String playlistName = widget.playlist.name;
    final bool isDeletingActivePlaylist = _isActivePlaylistQueue();
    final NavigatorState navigator = Navigator.of(context);
    deletePlaylist(widget.playlist);
    if (!context.mounted) return;
    showAppFeedback(context, '$playlistName playlist deleted');
    if (navigator.canPop()) {
      navigator.pop();
    }
    if (isDeletingActivePlaylist) {
      unawaited(stopPlayback());
    }
  }

  bool _isActivePlaylistQueue() {
    final AppPlaylist playlist = _playlist;
    if (playlist.songs.isEmpty) return false;
    if (currentPlaybackSourceTypeNotifier.value != 'Playlist') return false;
    if (currentPlaybackSourceNameNotifier.value != playlist.name) return false;
    if (currentIndexNotifier.value < 0) return false;
    if (globalQueue.length != playlist.songs.length) return false;

    for (var index = 0; index < globalQueue.length; index++) {
      if (_songId(globalQueue[index]) != _songId(playlist.songs[index])) {
        return false;
      }
    }

    return true;
  }
}

class _IconShellButton extends StatelessWidget {
  const _IconShellButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Icon(icon, color: color == Colors.white ? palette.accent : color, size: 20),
        ),
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

class _PlaylistSongTile extends StatelessWidget {
  const _PlaylistSongTile({
    required this.index,
    required this.title,
    required this.artist,
    required this.isActive,
    required this.isPlaying,
    required this.onTap,
    this.selectionMode = false,
    this.isSelected = false,
  });

  final int index;
  final String title;
  final String artist;
  final bool isActive;
  final bool isPlaying;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF453A).withOpacity(0.12)
              : isActive
                  ? palette.surfaceAlt
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF453A).withOpacity(0.42)
                : isActive
                    ? palette.accent.withOpacity(0.28)
                    : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (selectionMode) ...[
              Icon(
                isSelected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: isSelected ? const Color(0xFFFF453A) : palette.mutedText,
                size: 22,
              ),
              const SizedBox(width: 10),
            ],
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
            if (!selectionMode)
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

class _PlaylistEmptyState extends StatelessWidget {
  const _PlaylistEmptyState();

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
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
