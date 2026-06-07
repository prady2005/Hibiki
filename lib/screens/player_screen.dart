import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:just_audio/just_audio.dart';

import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/library_state.dart';
import '../services/lyrics_service.dart';
import '../services/theme_state.dart';
import '../widgets/app_feedback.dart';
import '../widgets/sleep_timer_sheet.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.onNext,
    required this.onPrev,
  });
  final Future<void> Function() onNext;
  final Future<void> Function() onPrev;

  static bool _isActive = false;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const double _lyricCenterHeightEstimate = 72;
  static const double _playerEstimatedLyricItemExtent = 54;
  static const double _syncedLyricScrollTolerance = 28;

  List<Map<String, dynamic>> lyrics = [];
  List<GlobalKey> lyricItemKeys = [];
  final Map<String, List<Map<String, dynamic>>> lyricsCache = {};
  final Map<String, Duration> lyricOffsets = <String, Duration>{};
  double? scrubProgress;
  int lyricLoadRequestId = 0;
  bool isLoadingLyrics = false;
  bool hasLoadedLyrics = false;
  bool showLyricsPanel = true;
  bool showPlaybackSourceTitle = false;

  int currentLyricIndex = 0;
  final ScrollController lyricsScrollController = ScrollController();
  bool _followingSyncedLyrics = true;
  bool _isAutoScrollingLyrics = false;
  double _playerLyricsEdgePadding = 0;
  double _playerLyricsViewportHeight = 0;

  late VoidCallback songListener;
  final ValueNotifier<bool> shuffleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<LoopMode> repeatModeNotifier = ValueNotifier<LoopMode>(LoopMode.off);
  StreamSubscription<bool>? _shuffleSubscription;
  Timer? _headerRotationTimer;
  late VoidCallback repeatModeListener;
  bool _ownsActivePlayerRoute = false;

  @override
  void initState() {
    super.initState();
    if (PlayerScreen._isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
    } else {
      PlayerScreen._isActive = true;
      _ownsActivePlayerRoute = true;
    }
    loadLyrics();
    _configureHeaderRotation();
    shuffleNotifier.value = player.shuffleModeEnabled;
    repeatModeNotifier.value = queueRepeatModeNotifier.value;

    _shuffleSubscription = player.shuffleModeEnabledStream.listen((isEnabled) {
      if (!mounted) return;
      shuffleNotifier.value = isEnabled;
    });
    repeatModeListener = () {
      if (!mounted) return;
      repeatModeNotifier.value = queueRepeatModeNotifier.value;
    };
    queueRepeatModeNotifier.addListener(repeatModeListener);

    songListener = () {
      if (!mounted) return;

      setState(() {
        lyrics = [];
        lyricItemKeys = [];
        currentLyricIndex = 0;
        isLoadingLyrics = true;
        hasLoadedLyrics = false;
        _followingSyncedLyrics = true;
      });

      if (lyricsScrollController.hasClients) {
        lyricsScrollController.jumpTo(lyricsScrollController.position.minScrollExtent);
      }

      loadLyrics();
      _configureHeaderRotation();
    };

    currentTrackRevisionNotifier.addListener(songListener);
    lyricsScrollController.addListener(_onPlayerLyricsScroll);
  }

  @override
  void dispose() {
    currentTrackRevisionNotifier.removeListener(songListener);
    queueRepeatModeNotifier.removeListener(repeatModeListener);
    lyricsScrollController.removeListener(_onPlayerLyricsScroll);
    if (_ownsActivePlayerRoute) {
      PlayerScreen._isActive = false;
    }
    _shuffleSubscription?.cancel();
    _headerRotationTimer?.cancel();
    lyricsScrollController.dispose();
    super.dispose();
  }

  void _onPlayerLyricsScroll() {
    if (_isAutoScrollingLyrics) return;
    _updatePlayerLyricsFollowingState();
  }

  bool _isPlayerViewingSyncedLyric() {
    if (!lyricsScrollController.hasClients || lyrics.isEmpty) return true;
    if (currentLyricIndex < 0 || currentLyricIndex >= lyricItemKeys.length) return true;

    final BuildContext? itemContext = lyricItemKeys[currentLyricIndex].currentContext;
    if (itemContext == null) return false;

    final RenderObject? renderObject = itemContext.findRenderObject();
    if (renderObject == null) return false;

    final RenderAbstractViewport viewport = RenderAbstractViewport.of(renderObject);
    final double targetOffset = viewport.getOffsetToReveal(renderObject, 0.5).offset;
    final double delta = (lyricsScrollController.offset - targetOffset).abs();
    return delta <= _syncedLyricScrollTolerance;
  }

  void _updatePlayerLyricsFollowingState() {
    _followingSyncedLyrics = _isPlayerViewingSyncedLyric();
  }

  double _estimatedPlayerLyricOffset(int index) {
    final double lineTop = _playerLyricsEdgePadding + (index * _playerEstimatedLyricItemExtent);
    final double viewportCenter = _playerLyricsViewportHeight > 0
        ? _playerLyricsViewportHeight / 2
        : _lyricCenterHeightEstimate;
    return lineTop - (viewportCenter - (_playerEstimatedLyricItemExtent / 2));
  }

  void _scrollPlayerLyricsToCurrentAfterLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_followingSyncedLyrics || lyrics.isEmpty) return;
      unawaited(scrollToCurrent(currentLyricIndex));
    });
  }

  Future<void> loadLyrics() async {
    final int requestId = ++lyricLoadRequestId;
    final String title = currentSongNotifier.value;
    final String artist = currentArtistNotifier.value;
    final String key = _lyricsKey;

    if (lyricsCache.containsKey(key)) {
      final List<Map<String, dynamic>> cachedLyrics = lyricsCache[key]!;
      if (cachedLyrics.isEmpty) {
        lyricsCache.remove(key);
      } else {
        if (!mounted) return;
        setState(() {
          lyrics = cachedLyrics;
          lyricItemKeys = List.generate(lyrics.length, (_) => GlobalKey());
          isLoadingLyrics = false;
          hasLoadedLyrics = true;
        });
        _scrollPlayerLyricsToCurrentAfterLoad();
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      isLoadingLyrics = true;
      hasLoadedLyrics = false;
    });

    final List<Map<String, dynamic>> data = await fetchLyrics(title, artist);
    if (data.isNotEmpty) {
      lyricsCache[key] = data;
    } else {
      lyricsCache.remove(key);
    }

    if (!mounted || requestId != lyricLoadRequestId || key != _lyricsKey) return;
    setState(() {
      lyrics = data;
      lyricItemKeys = List.generate(lyrics.length, (_) => GlobalKey());
      isLoadingLyrics = false;
      hasLoadedLyrics = true;
    });
    _scrollPlayerLyricsToCurrentAfterLoad();
  }

  String get _lyricsKey {
    final String id = currentSongIdNotifier.value;
    if (id.isNotEmpty) return id;
    return '${currentArtistNotifier.value}-${currentSongNotifier.value}';
  }

  Duration get _currentLyricOffset => lyricOffsets[_lyricsKey] ?? Duration.zero;

  void _changeLyricOffset(Duration delta) {
    final String key = _lyricsKey;
    final Duration nextOffset = (lyricOffsets[key] ?? Duration.zero) + delta;
    setState(() {
      lyricOffsets[key] = nextOffset;
    });
  }

  void _resetLyricOffset() {
    setState(() {
      lyricOffsets.remove(_lyricsKey);
    });
  }

  void updateCurrentLyric(Duration position) {
    if (lyrics.isEmpty) return;

    final Duration adjustedPosition = position + _currentLyricOffset;
    var newIndex = 0;
    for (var i = 0; i < lyrics.length; i++) {
      final time = lyrics[i]['time'] as Duration;
      if (adjustedPosition >= time) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != currentLyricIndex) {
      final bool shouldFollow = _followingSyncedLyrics;
      currentLyricIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (shouldFollow) {
          unawaited(scrollToCurrent(newIndex));
        } else {
          _updatePlayerLyricsFollowingState();
        }
      });
    }
  }

  Future<void> scrollToCurrent(int index) async {
    if (!lyricsScrollController.hasClients) return;
    if (index < 0 || index >= lyrics.length) return;

    _isAutoScrollingLyrics = true;
    try {
      for (var attempt = 0; attempt < 10; attempt++) {
        if (!mounted) return;

        final BuildContext? itemContext = lyricItemKeys[index].currentContext;
        if (itemContext != null) {
          final RenderObject? renderObject = itemContext.findRenderObject();
          if (renderObject != null) {
            final RenderAbstractViewport viewport = RenderAbstractViewport.of(renderObject);
            final double targetOffset = viewport.getOffsetToReveal(renderObject, 0.5).offset;

            await lyricsScrollController.animateTo(
              targetOffset.clamp(
                lyricsScrollController.position.minScrollExtent,
                lyricsScrollController.position.maxScrollExtent,
              ),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
            return;
          }
        }

        final double estimatedOffset = _estimatedPlayerLyricOffset(index);
        lyricsScrollController.jumpTo(
          estimatedOffset.clamp(
            lyricsScrollController.position.minScrollExtent,
            lyricsScrollController.position.maxScrollExtent,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 24));
      }
    } finally {
      _isAutoScrollingLyrics = false;
      if (mounted) {
        _followingSyncedLyrics = true;
      }
    }
  }

  void toggleShuffle() {
    final bool nextState = !shuffleNotifier.value;
    setShuffleEnabled(nextState);
    shuffleNotifier.value = nextState;
  }

  void toggleRepeat() {
    final LoopMode nextMode = repeatModeNotifier.value == LoopMode.off
        ? LoopMode.all
        : repeatModeNotifier.value == LoopMode.all
            ? LoopMode.one
            : LoopMode.off;
    unawaited(setQueueRepeatMode(nextMode));
    repeatModeNotifier.value = nextMode;
  }

  void _showQueueSheet() {
    final AppThemePalette palette = activeAppPalette(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const _QueueSheet(),
    );
  }

  void _showFullScreenLyrics() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullScreenLyricsPage(
          lyricsCache: lyricsCache,
          lyricOffsets: lyricOffsets,
          onOffsetChanged: (offset) {
            setState(() {
              lyricOffsets[_lyricsKey] = offset;
            });
          },
        ),
      ),
    );
  }

  void _showSleepTimerSheet() {
    final AppThemePalette palette = activeAppPalette(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const SleepTimerSheet(),
    );
  }

  void _showPlayerOptionsSheet() {
    final AppThemePalette palette = activeAppPalette(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _PlayerOptionsSheet(
        showLyricsPanel: showLyricsPanel,
        onAddToPlaylist: () {
          Navigator.pop(context);
          _showAddToPlaylistSheet();
        },
        onToggleLyrics: () {
          setState(() {
            showLyricsPanel = !showLyricsPanel;
          });
          showAppFeedback(
            context,
            showLyricsPanel ? 'Lyrics are visible' : 'Lyrics are hidden',
          );
          Navigator.pop(context);
        },
        onAddToQueue: () {
          final dynamic song = _currentSong;
          if (song == null) return;
          addSongToQueue(song);
          showAppFeedback(context, '${_queueSongTitle(song)} added to queue');
          Navigator.pop(context);
        },
        onShowSleepTimer: () {
          Navigator.pop(context);
          _showSleepTimerSheet();
        },
        onShowQueue: () {
          Navigator.pop(context);
          _showQueueSheet();
        },
      ),
    );
  }

  void _showAddToPlaylistSheet() {
    final dynamic song = _currentSong;
    if (song == null) {
      showAppFeedback(context, 'No song is currently playing');
      return;
    }

    final AppThemePalette palette = activeAppPalette(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _AddToPlaylistSheet(song: song),
    );
  }

  dynamic get _currentSong {
    final int currentIndex = currentIndexNotifier.value;
    if (currentIndex < 0 || currentIndex >= globalQueue.length) return null;
    return globalQueue[currentIndex];
  }

  void _configureHeaderRotation() {
    _headerRotationTimer?.cancel();
    showPlaybackSourceTitle = false;

    if (currentPlaybackSourceNameNotifier.value.trim().isEmpty) return;

    _headerRotationTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      if (currentPlaybackSourceNameNotifier.value.trim().isEmpty) return;
      setState(() {
        showPlaybackSourceTitle = !showPlaybackSourceTitle;
      });
    });
  }

  String formatTime(Duration duration) {
    final String minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatLyricOffset(Duration offset) {
    if (offset == Duration.zero) return '0.0s';
    final sign = offset.isNegative ? '-' : '+';
    final double seconds = offset.inMilliseconds.abs() / 1000;
    return '$sign${seconds.toStringAsFixed(1)}s';
  }

  Widget buildAlbumArt(String url) {
    return Container(
      width: 292,
      height: 292,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.42),
            blurRadius: 36,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _AlbumArtFallback();
                },
              )
            : _AlbumArtFallback(),
      ),
    );
  }

  Widget _buildNowPlayingHeader() {
    final AppThemePalette palette = activeAppPalette(context);
    final String sourceName = currentPlaybackSourceNameNotifier.value.trim();
    final String title =
        sourceName.isNotEmpty && showPlaybackSourceTitle ? sourceName : currentSongNotifier.value;

    return SizedBox(
      width: MediaQuery.sizeOf(context).width - 128,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Now playing',
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Text(
              title,
              key: ValueKey<String>(title),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final Color activeControlForeground = readableTextOn(palette.accent);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TopBarButton(
                        icon: CupertinoIcons.chevron_down,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    _buildNowPlayingHeader(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _TopBarButton(
                        icon: CupertinoIcons.ellipsis,
                        onTap: _showPlayerOptionsSheet,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ValueListenableBuilder<String>(
                valueListenable: currentImageNotifier,
                builder: (context, value, child) => buildAlbumArt(value),
              ),
              const SizedBox(height: 26),
              ValueListenableBuilder<String>(
                valueListenable: currentSongNotifier,
                builder: (context, title, child) {
                  return Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                      letterSpacing: -0.6,
                      height: 1.08,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: currentArtistNotifier,
                builder: (context, artist, child) {
                  return Text(
                    artist,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<int>(
                valueListenable: currentIndexNotifier,
                builder: (context, currentIndex, child) {
                  final dynamic currentSong = currentIndex >= 0 && currentIndex < globalQueue.length
                      ? globalQueue[currentIndex]
                      : null;

                  return ValueListenableBuilder<Set<String>>(
                    valueListenable: favoriteSongIdsNotifier,
                    builder: (context, _, child) {
                      final bool isFavorite = isSongFavorite(currentSong);

                      return GestureDetector(
                        onTap: currentSong == null
                            ? null
                            : () {
                                final bool wasFavorite = isSongFavorite(currentSong);
                                toggleFavoriteSong(currentSong);
                                showAppFeedback(
                                  context,
                                  wasFavorite
                                      ? 'Removed from favourite songs'
                                      : 'Added to favourite songs',
                                );
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: isFavorite
                                ? const Color(0xFFFF453A).withOpacity(0.16)
                                : palette.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isFavorite
                                  ? const Color(0xFFFF453A).withOpacity(0.42)
                                  : palette.border,
                            ),
                          ),
                          child: Icon(
                            isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                            color: isFavorite ? const Color(0xFFFF453A) : palette.accent,
                            size: 20,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 22),
              ValueListenableBuilder<Duration>(
                valueListenable: currentPositionNotifier,
                builder: (context, position, child) {
                  return ValueListenableBuilder<Duration>(
                    valueListenable: currentDurationNotifier,
                    builder: (context, duration, child) {
                      final double liveProgress = duration.inMilliseconds == 0
                          ? 0.0
                          : position.inMilliseconds / duration.inMilliseconds;
                      final double progress = (scrubProgress ?? liveProgress).clamp(0.0, 1.0);
                      final displayPosition = scrubProgress == null
                          ? position
                          : Duration(
                              milliseconds: (duration.inMilliseconds * scrubProgress!).round(),
                            );

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: palette.accent,
                              inactiveTrackColor: palette.mutedText.withOpacity(0.24),
                              thumbColor: palette.accent,
                              overlayColor: palette.accent.withOpacity(0.1),
                            ),
                            child: Slider(
                              value: progress,
                              onChangeStart: (value) {
                                setState(() {
                                  scrubProgress = value;
                                });
                              },
                              onChanged: (value) {
                                setState(() {
                                  scrubProgress = value;
                                });
                              },
                              onChangeEnd: (value) async {
                                final seekTo = Duration(
                                  milliseconds: (duration.inMilliseconds * value).round(),
                                );
                                currentPositionNotifier.value = seekTo;
                                setState(() {
                                  scrubProgress = null;
                                });
                                await player.seek(seekTo);
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatTime(displayPosition),
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                formatTime(duration),
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: palette.border,
                  ),
                ),
                child: Row(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: shuffleNotifier,
                      builder: (context, isShuffleOn, child) {
                        return GestureDetector(
                          onTap: toggleShuffle,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: isShuffleOn ? palette.accent : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.shuffle,
                              color: isShuffleOn ? activeControlForeground : palette.mutedText,
                              size: 20,
                            ),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    _ControlButton(
                      icon: CupertinoIcons.backward_end_fill,
                      onTap: () async {
                        await widget.onPrev();
                      },
                    ),
                    const SizedBox(width: 14),
                    ValueListenableBuilder<bool>(
                      valueListenable: isPlayingNotifier,
                      builder: (context, isPlaying, child) {
                        return _PrimaryPlayButton(
                          icon: isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                          onTap: togglePlayPause,
                        );
                      },
                    ),
                    const SizedBox(width: 14),
                    _ControlButton(
                      icon: CupertinoIcons.forward_end_fill,
                      onTap: () async {
                        await widget.onNext();
                      },
                    ),
                    const Spacer(),
                    ValueListenableBuilder<LoopMode>(
                      valueListenable: repeatModeNotifier,
                      builder: (context, repeatMode, child) {
                        final isRepeatOn = repeatMode != LoopMode.off;

                        return GestureDetector(
                          onTap: toggleRepeat,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: isRepeatOn ? palette.accent : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.repeat,
                                  color: isRepeatOn ? activeControlForeground : palette.mutedText,
                                  size: 20,
                                ),
                                if (repeatMode == LoopMode.one)
                                  Positioned(
                                    right: 8,
                                    top: 7,
                                    child: Text(
                                      '1',
                                      style: TextStyle(
                                        color:
                                            isRepeatOn ? activeControlForeground : palette.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (showLyricsPanel) ...[
                const SizedBox(height: 26),
                GestureDetector(
                  onTap: lyrics.isEmpty ? null : _showFullScreenLyrics,
                  child: Container(
                    width: double.infinity,
                    height: 320,
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: palette.border,
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                          child: Row(
                            children: [
                              Text(
                                'Lyrics',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                isLoadingLyrics
                                    ? 'Fetching...'
                                    : lyrics.isEmpty
                                        ? 'Unavailable'
                                        : _currentLyricOffset == Duration.zero
                                            ? 'Synced'
                                            : _formatLyricOffset(_currentLyricOffset),
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (lyrics.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: () => _changeLyricOffset(
                                    const Duration(milliseconds: -500),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.minus_circle,
                                    color: palette.mutedText,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _changeLyricOffset(
                                    const Duration(milliseconds: 500),
                                  ),
                                  onLongPress: _resetLyricOffset,
                                  child: Icon(
                                    CupertinoIcons.plus_circle,
                                    color: palette.mutedText,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              _playerLyricsEdgePadding =
                                  ((constraints.maxHeight / 2) - (_lyricCenterHeightEstimate / 2))
                                      .clamp(0.0, 200.0);
                              _playerLyricsViewportHeight = constraints.maxHeight;

                              if (lyrics.isEmpty) {
                                return Center(
                                  child: Text(
                                    isLoadingLyrics || !hasLoadedLyrics
                                        ? 'Loading lyrics...'
                                        : 'No synced lyrics found',
                                    style: TextStyle(
                                      color: palette.mutedText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              }

                              return StreamBuilder<Duration>(
                                stream: player.positionStream,
                                builder: (context, snapshot) {
                                  final Duration position = snapshot.data ?? Duration.zero;
                                  updateCurrentLyric(position);
                                  final int visibleLyricCount = math.min(
                                    lyrics.length,
                                    lyricItemKeys.length,
                                  );

                                  if (visibleLyricCount == 0) {
                                    return Center(
                                      child: Text(
                                        'Loading lyrics...',
                                        style: TextStyle(
                                          color: palette.mutedText,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    );
                                  }

                                  return ListView.builder(
                                    controller: lyricsScrollController,
                                    padding: EdgeInsets.fromLTRB(
                                      24,
                                      _playerLyricsEdgePadding,
                                      24,
                                      _playerLyricsEdgePadding,
                                    ),
                                    itemCount: visibleLyricCount,
                                    itemBuilder: (context, index) {
                                      final isActive = index == currentLyricIndex;

                                      return AnimatedContainer(
                                        key: lyricItemKeys[index],
                                        duration: const Duration(milliseconds: 180),
                                        curve: Curves.easeOutCubic,
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          lyrics[index]['text'] as String,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: isActive
                                                ? palette.text
                                                : palette.mutedText.withOpacity(0.78),
                                            fontSize: isActive ? 21 : 16,
                                            height: 1.3,
                                            fontWeight:
                                                isActive ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerOptionsSheet extends StatelessWidget {
  const _PlayerOptionsSheet({
    required this.showLyricsPanel,
    required this.onAddToPlaylist,
    required this.onToggleLyrics,
    required this.onAddToQueue,
    required this.onShowSleepTimer,
    required this.onShowQueue,
  });

  final bool showLyricsPanel;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onToggleLyrics;
  final VoidCallback onAddToQueue;
  final VoidCallback onShowSleepTimer;
  final VoidCallback onShowQueue;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'More options',
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
            const SizedBox(height: 8),
            _PlayerMenuTile(
              icon: CupertinoIcons.music_note_list,
              title: 'Add to playlist',
              onTap: onAddToPlaylist,
            ),
            _PlayerMenuTile(
              icon: showLyricsPanel ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
              title: showLyricsPanel ? 'Turn lyrics off' : 'Turn lyrics on',
              onTap: onToggleLyrics,
            ),
            _PlayerMenuTile(
              icon: CupertinoIcons.plus_circle,
              title: 'Add song to queue',
              onTap: onAddToQueue,
            ),
            _PlayerMenuTile(
              icon: CupertinoIcons.timer,
              title: 'Sleep timer',
              onTap: onShowSleepTimer,
            ),
            _PlayerMenuTile(
              icon: CupertinoIcons.list_bullet,
              title: 'Go to queue',
              onTap: onShowQueue,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerMenuTile extends StatelessWidget {
  const _PlayerMenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: palette.accent, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: palette.mutedText,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddToPlaylistSheet extends StatelessWidget {
  const _AddToPlaylistSheet({required this.song});

  final dynamic song;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final List<AppPlaylist> playlists = playlistsNotifier.value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add to playlist',
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
            const SizedBox(height: 8),
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  'No playlists yet',
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              ...playlists.map((playlist) {
                return _PlayerMenuTile(
                  icon: CupertinoIcons.music_albums_fill,
                  title: playlist.name,
                  onTap: () {
                    final bool added = addSongToPlaylist(playlist, song);
                    showAppFeedback(
                      context,
                      added ? 'Added to ${playlist.name}' : 'Song is already in ${playlist.name}',
                    );
                    Navigator.pop(context);
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _FullScreenLyricsPage extends StatefulWidget {
  const _FullScreenLyricsPage({
    required this.lyricsCache,
    required this.lyricOffsets,
    required this.onOffsetChanged,
  });

  final Map<String, List<Map<String, dynamic>>> lyricsCache;
  final Map<String, Duration> lyricOffsets;
  final ValueChanged<Duration> onOffsetChanged;

  @override
  State<_FullScreenLyricsPage> createState() => _FullScreenLyricsPageState();
}

class _FullScreenLyricsPageState extends State<_FullScreenLyricsPage> {
  static const double _lyricCenterHeightEstimate = 86;
  static const double _estimatedLyricItemExtent = 68;
  static const double _syncedLyricScrollTolerance = 28;

  final ScrollController _controller = ScrollController();
  List<GlobalKey> _keys = <GlobalKey>[];
  List<Map<String, dynamic>> _lyrics = <Map<String, dynamic>>[];
  String _title = '';
  int _currentIndex = 0;
  late Duration _offset;
  bool _viewingSyncedLyric = true;
  bool _isAutoScrollingLyrics = false;
  bool _isLoadingLyrics = true;
  bool _scrollToTopOnNextLoad = false;
  int _lyricLoadRequestId = 0;
  double _edgePadding = 0;
  double _viewportHeight = 0;
  late VoidCallback _trackListener;

  @override
  void initState() {
    super.initState();
    _title = currentSongNotifier.value;
    _offset = _currentLyricOffset;
    _controller.addListener(_onLyricsScroll);
    _trackListener = _onTrackChanged;
    currentTrackRevisionNotifier.addListener(_trackListener);
    _loadLyrics();
  }

  @override
  void dispose() {
    currentTrackRevisionNotifier.removeListener(_trackListener);
    _controller.removeListener(_onLyricsScroll);
    _controller.dispose();
    super.dispose();
  }

  String get _lyricsKey {
    final String id = currentSongIdNotifier.value;
    if (id.isNotEmpty) return id;
    return '${currentArtistNotifier.value}-${currentSongNotifier.value}';
  }

  Duration get _currentLyricOffset => widget.lyricOffsets[_lyricsKey] ?? Duration.zero;

  void _onTrackChanged() {
    if (!mounted) return;

    _scrollToTopOnNextLoad = true;
    if (_controller.hasClients) {
      _controller.jumpTo(_controller.position.minScrollExtent);
    }

    setState(() {
      _title = currentSongNotifier.value;
      _offset = _currentLyricOffset;
      _currentIndex = 0;
      _lyrics = <Map<String, dynamic>>[];
      _keys = <GlobalKey>[];
      _isLoadingLyrics = true;
      _viewingSyncedLyric = true;
    });

    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    final int requestId = ++_lyricLoadRequestId;
    final String key = _lyricsKey;
    final String title = currentSongNotifier.value;
    final String artist = currentArtistNotifier.value;

    if (widget.lyricsCache.containsKey(key)) {
      final List<Map<String, dynamic>> cachedLyrics = widget.lyricsCache[key]!;
      if (cachedLyrics.isEmpty) {
        widget.lyricsCache.remove(key);
      } else {
        if (!mounted || requestId != _lyricLoadRequestId || key != _lyricsKey) return;
        _applyLoadedLyrics(cachedLyrics, requestId: requestId);
        return;
      }
    }

    if (!mounted || requestId != _lyricLoadRequestId) return;
    setState(() => _isLoadingLyrics = true);

    final List<Map<String, dynamic>> data = await fetchLyrics(title, artist);
    if (data.isNotEmpty) {
      widget.lyricsCache[key] = data;
    } else {
      widget.lyricsCache.remove(key);
    }

    if (!mounted || requestId != _lyricLoadRequestId || key != _lyricsKey) return;
    _applyLoadedLyrics(data, requestId: requestId);
  }

  void _applyLoadedLyrics(List<Map<String, dynamic>> data, {required int requestId}) {
    if (!mounted || requestId != _lyricLoadRequestId) return;

    final bool scrollToTop = _scrollToTopOnNextLoad;
    _scrollToTopOnNextLoad = false;

    setState(() {
      _lyrics = data;
      _keys = List.generate(data.length, (_) => GlobalKey());
      _isLoadingLyrics = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || requestId != _lyricLoadRequestId) return;
      if (!_controller.hasClients) return;

      if (scrollToTop) {
        _controller.jumpTo(_controller.position.minScrollExtent);
        _updateViewingState();
        return;
      }

      await _scrollToCurrent(_currentIndex);
      _updateViewingState();
    });
  }

  void _onLyricsScroll() {
    if (_isAutoScrollingLyrics) return;
    _updateViewingState();
  }

  void _updateViewingState() {
    if (!mounted) return;
    final bool viewing = _isViewingSyncedLyric();
    if (viewing != _viewingSyncedLyric) {
      setState(() => _viewingSyncedLyric = viewing);
    }
  }

  bool _isViewingSyncedLyric() {
    if (!_controller.hasClients || _lyrics.isEmpty) return true;
    if (_currentIndex < 0 || _currentIndex >= _keys.length) return true;

    final BuildContext? itemContext = _keys[_currentIndex].currentContext;
    if (itemContext == null) return false;

    final RenderObject? renderObject = itemContext.findRenderObject();
    if (renderObject == null) return false;

    final RenderAbstractViewport viewport = RenderAbstractViewport.of(renderObject);
    final double targetOffset = viewport.getOffsetToReveal(renderObject, 0.5).offset;
    final double delta = (_controller.offset - targetOffset).abs();
    return delta <= _syncedLyricScrollTolerance;
  }

  double _estimatedCenteredOffset(int index) {
    final double lineTop = _edgePadding + (index * _estimatedLyricItemExtent);
    final double viewportCenter = _viewportHeight > 0
        ? _viewportHeight / 2
        : _lyricCenterHeightEstimate;
    return lineTop - (viewportCenter - (_estimatedLyricItemExtent / 2));
  }

  void _updateCurrentLyric(Duration position) {
    if (_lyrics.isEmpty) return;

    final Duration adjustedPosition = position + _offset;
    var newIndex = 0;
    for (var i = 0; i < _lyrics.length; i++) {
      final time = _lyrics[i]['time'] as Duration;
      if (adjustedPosition >= time) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _currentIndex) {
      final bool shouldFollow = _viewingSyncedLyric;
      _currentIndex = newIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (shouldFollow) {
          unawaited(_scrollToCurrent(_currentIndex));
        } else {
          _updateViewingState();
        }
      });
    }
  }

  Future<void> _scrollToCurrent(int index) async {
    if (!_controller.hasClients || index < 0 || index >= _lyrics.length) return;

    _isAutoScrollingLyrics = true;
    try {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!mounted) return;

      final BuildContext? itemContext = _keys[index].currentContext;
      if (itemContext != null) {
        final RenderObject? renderObject = itemContext.findRenderObject();
        if (renderObject != null) {
          final RenderAbstractViewport viewport = RenderAbstractViewport.of(renderObject);
          final double targetOffset = viewport.getOffsetToReveal(renderObject, 0.5).offset;

          await _controller.animateTo(
            targetOffset.clamp(
              _controller.position.minScrollExtent,
              _controller.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
          if (mounted) {
            _updateViewingState();
          }
          return;
        }
      }

      final double estimatedOffset = _estimatedCenteredOffset(index);
      _controller.jumpTo(
        estimatedOffset.clamp(
          _controller.position.minScrollExtent,
          _controller.position.maxScrollExtent,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
    } finally {
      _isAutoScrollingLyrics = false;
      if (mounted) {
        _updateViewingState();
      }
    }
  }

  Future<void> _seekToLyric(int index) async {
    if (index < 0 || index >= _lyrics.length) return;
    final lyricTime = _lyrics[index]['time'] as Duration;
    final Duration seekTo = lyricTime - _offset;
    await player.seek(seekTo.isNegative ? Duration.zero : seekTo);
  }

  void _shiftOffset(Duration delta) {
    setState(() {
      _offset += delta;
      widget.lyricOffsets[_lyricsKey] = _offset;
    });
    widget.onOffsetChanged(_offset);
  }

  void _resetOffset() {
    setState(() {
      _offset = Duration.zero;
      widget.lyricOffsets[_lyricsKey] = Duration.zero;
    });
    widget.onOffsetChanged(_offset);
  }

  String _formatOffset(Duration offset) {
    if (offset == Duration.zero) return '0.0s';
    final sign = offset.isNegative ? '-' : '+';
    final double seconds = offset.inMilliseconds.abs() / 1000;
    return '$sign${seconds.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _TopBarButton(
                    icon: CupertinoIcons.xmark,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title.isEmpty ? 'Lyrics' : _title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatOffset(_offset),
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  _LyricSyncButton(
                    label: '-0.5s',
                    onTap: () => _shiftOffset(const Duration(milliseconds: -500)),
                  ),
                  const SizedBox(width: 10),
                  _LyricSyncButton(
                    label: '+0.5s',
                    onTap: () => _shiftOffset(const Duration(milliseconds: 500)),
                  ),
                  const SizedBox(width: 10),
                  _LyricSyncButton(
                    label: 'Reset',
                    onTap: _resetOffset,
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _edgePadding = ((constraints.maxHeight / 2) -
                          (_lyricCenterHeightEstimate / 2))
                      .clamp(0.0, 320.0);
                  _viewportHeight = constraints.maxHeight;

                  return Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      StreamBuilder<Duration>(
                        stream: player.positionStream,
                        builder: (context, snapshot) {
                          _updateCurrentLyric(snapshot.data ?? Duration.zero);

                          if (_isLoadingLyrics) {
                            return Center(
                              child: CupertinoActivityIndicator(color: palette.accent),
                            );
                          }

                          if (_lyrics.isEmpty) {
                            return Center(
                              child: Text(
                                'No synced lyrics found',
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            controller: _controller,
                            padding: EdgeInsets.fromLTRB(
                              24,
                              _edgePadding,
                              24,
                              _edgePadding + 72,
                            ),
                            itemCount: _lyrics.length,
                            itemBuilder: (context, index) {
                              final isActive = index == _currentIndex;
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _seekToLyric(index),
                                child: AnimatedContainer(
                                  key: _keys[index],
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  child: Text(
                                    _lyrics[index]['text'] as String,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isActive
                                          ? palette.text
                                          : palette.mutedText.withOpacity(0.72),
                                      fontSize: isActive ? 30 : 20,
                                      height: 1.25,
                                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 18,
                        child: Center(
                          child: _SyncLyricsLineButton(
                            enabled: !_viewingSyncedLyric && !_isLoadingLyrics && _lyrics.isNotEmpty,
                            onTap: () {
                              setState(() => _viewingSyncedLyric = true);
                              unawaited(_scrollToCurrent(_currentIndex));
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncLyricsLineButton extends StatelessWidget {
  const _SyncLyricsLineButton({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final Color foreground = enabled ? palette.text : palette.mutedText.withOpacity(0.45);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: palette.surface.withOpacity(0.96),
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: enabled ? palette.border : palette.border.withOpacity(0.55),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  size: 15,
                  color: foreground,
                ),
                const SizedBox(width: 8),
                Text(
                  'Sync',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricSyncButton extends StatelessWidget {
  const _LyricSyncButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: palette.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.icon,
    this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Icon(
          icon,
          color: palette.accent,
          size: 20,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      onTap: () async {
        await onTap();
      },
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: palette.border),
        ),
        child: Icon(
          icon,
          color: palette.accent,
          size: 24,
        ),
      ),
    );
  }
}

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: palette.background,
          size: 30,
        ),
      ),
    );
  }
}

class _QueueSongTile extends StatelessWidget {
  const _QueueSongTile({
    super.key,
    required this.index,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.onRemove,
  });

  final int index;
  final String title;
  final String artist;
  final String imageUrl;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$index',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl.isEmpty
                ? const _QueueArtFallback()
                : Image.network(
                    imageUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const _QueueArtFallback();
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
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRemove,
            icon: Icon(
              CupertinoIcons.minus_circle,
              color: palette.mutedText,
              size: 21,
            ),
          ),
          Icon(
            CupertinoIcons.line_horizontal_3,
            color: palette.mutedText,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _QueueSheet extends StatefulWidget {
  const _QueueSheet();

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> librarySongs = <dynamic>[];
  bool isLoadingLibrary = false;
  String query = '';

  @override
  void initState() {
    super.initState();
    _loadLibrarySongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLibrarySongs() async {
    setState(() {
      isLoadingLibrary = true;
    });

    try {
      final List<dynamic> songs = await fetchSongs();
      if (!mounted) return;
      setState(() {
        librarySongs = songs
          ..sort((a, b) =>
              _queueSongTitle(a).toLowerCase().compareTo(_queueSongTitle(b).toLowerCase()));
        isLoadingLibrary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        librarySongs = <dynamic>[];
        isLoadingLibrary = false;
      });
    }
  }

  List<dynamic> get _matchingSongs {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) return <dynamic>[];

    return librarySongs
        .where((song) {
          return _queueSongTitle(song).toLowerCase().contains(needle) ||
              _queueSongArtist(song).toLowerCase().contains(needle);
        })
        .take(8)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.76,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              queueRevisionNotifier,
              currentIndexNotifier,
            ]),
            builder: (context, child) {
              final List<dynamic> upcomingSongs = upcomingQueueSnapshot();
              final List<dynamic> matchingSongs = _matchingSongs;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StreamBuilder<bool>(
                          stream: player.shuffleModeEnabledStream,
                          initialData: player.shuffleModeEnabled,
                          builder: (context, snapshot) {
                            final bool isShuffleOn = snapshot.data ?? false;
                            return Text(
                              isShuffleOn ? 'Up next - shuffled' : 'Up next',
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          CupertinoIcons.xmark,
                          color: palette.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    style: TextStyle(color: palette.text),
                    cursorColor: palette.accent,
                    decoration: InputDecoration(
                      hintText: 'Add a song to queue',
                      hintStyle: TextStyle(
                        color: palette.mutedText.withOpacity(0.85),
                      ),
                      prefixIcon: Icon(
                        CupertinoIcons.search,
                        color: palette.mutedText,
                        size: 20,
                      ),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  query = '';
                                });
                              },
                              icon: Icon(
                                CupertinoIcons.xmark_circle_fill,
                                color: palette.mutedText,
                                size: 18,
                              ),
                            ),
                      filled: true,
                      fillColor: palette.surfaceAlt.withOpacity(0.72),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: palette.accent.withOpacity(0.55)),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        query = value;
                      });
                    },
                  ),
                  if (query.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    if (isLoadingLibrary)
                      Center(
                        child: CupertinoActivityIndicator(color: palette.accent),
                      )
                    else if (matchingSongs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No songs found',
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 210),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: matchingSongs.length,
                          itemBuilder: (context, index) {
                            final song = matchingSongs[index];
                            return _QueueAddSongTile(
                              title: _queueSongTitle(song),
                              artist: _queueSongArtist(song),
                              imageUrl:
                                  _queueSongId(song).isEmpty ? '' : getImageUrl(_queueSongId(song)),
                              onTap: () {
                                addSongToQueue(song);
                                showAppFeedback(
                                  context,
                                  '${_queueSongTitle(song)} added to queue',
                                );
                                _searchController.clear();
                                setState(() {
                                  query = '';
                                });
                              },
                            );
                          },
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Expanded(
                    child: upcomingSongs.isEmpty
                        ? Center(
                            child: Text(
                              'No songs in queue',
                              style: TextStyle(
                                color: palette.mutedText,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            proxyDecorator: (child, index, animation) {
                              return Material(
                                color: Colors.transparent,
                                child: child,
                              );
                            },
                            itemCount: upcomingSongs.length,
                            onReorder: moveUpcomingQueueItem,
                            itemBuilder: (context, index) {
                              final song = upcomingSongs[index];
                              return _QueueSongTile(
                                key: ValueKey('${_queueSongId(song)}-${identityHashCode(song)}'),
                                index: index + 1,
                                title: _queueSongTitle(song),
                                artist: _queueSongArtist(song),
                                imageUrl: _queueSongId(song).isEmpty
                                    ? ''
                                    : getImageUrl(_queueSongId(song)),
                                onRemove: () {
                                  removeUpcomingQueueItem(index);
                                  showAppFeedback(
                                    context,
                                    '${_queueSongTitle(song)} removed from queue',
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QueueAddSongTile extends StatelessWidget {
  const _QueueAddSongTile({
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl.isEmpty
                  ? const _QueueArtFallback()
                  : Image.network(
                      imageUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const _QueueArtFallback();
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.plus_circle_fill,
              color: palette.accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueArtFallback extends StatelessWidget {
  const _QueueArtFallback();

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      width: 48,
      height: 48,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.music_note,
        color: palette.mutedText,
        size: 20,
      ),
    );
  }
}

class _AlbumArtFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.music_note,
        color: palette.mutedText,
        size: 70,
      ),
    );
  }
}

String _queueSongId(dynamic song) {
  final id = song is Map ? song['Id'] : null;
  return id?.toString() ?? '';
}

String _queueSongTitle(dynamic song) {
  final title = song is Map ? song['Name'] : null;
  return title?.toString() ?? 'Unknown track';
}

String _queueSongArtist(dynamic song) {
  if (song is! Map) return 'Unknown';
  final artists = song['Artists'];
  if (artists is List && artists.isNotEmpty && artists.first != null) {
    return artists.first.toString();
  }
  return 'Unknown';
}
