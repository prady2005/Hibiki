import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'audio_preferences_settings.dart';
import 'equalizer_settings.dart';
import 'library_state.dart';

final AndroidEqualizer mainEqualizer = AndroidEqualizer();
final AndroidEqualizer crossfadeEqualizer = AndroidEqualizer();

final player = AudioPlayer(
  audioPipeline: AudioPipeline(
    androidAudioEffects: <AndroidAudioEffect>[mainEqualizer],
  ),
);
final AudioPlayer _crossfadePlayer = AudioPlayer(
  audioPipeline: AudioPipeline(
    androidAudioEffects: <AndroidAudioEffect>[crossfadeEqualizer],
  ),
);

AndroidEqualizer get playbackEqualizer => mainEqualizer;

Future<void> Function()? ensureBackgroundAudioService;

VoidCallback? syncBackgroundNotification;
void Function({
  required String id,
  required String title,
  required String artist,
  required String album,
  String? imageUrl,
  Duration? duration,
})? updateBackgroundMediaItem;

void _notifyBackgroundPlayback() {
  syncBackgroundNotification?.call();
}

final currentSongNotifier = ValueNotifier<String>('Nothing playing');
final currentSongIdNotifier = ValueNotifier<String>('');
final currentTrackRevisionNotifier = ValueNotifier<int>(0);
final currentPlaybackSourceTypeNotifier = ValueNotifier<String>('');
final currentPlaybackSourceNameNotifier = ValueNotifier<String>('');
final currentImageNotifier = ValueNotifier<String>('');
final currentArtistNotifier = ValueNotifier<String>('Unknown');
final currentPositionNotifier = ValueNotifier<Duration>(Duration.zero);
final currentDurationNotifier = ValueNotifier<Duration>(Duration.zero);
final isPlayingNotifier = ValueNotifier<bool>(false);
final queueRevisionNotifier = ValueNotifier<int>(0);
final queueRepeatModeNotifier = ValueNotifier<LoopMode>(LoopMode.off);
final sleepTimerEndsAtNotifier = ValueNotifier<DateTime?>(null);

class SourcePlaybackPreset {
  const SourcePlaybackPreset({required this.shuffleEnabled, required this.repeatMode});

  final bool shuffleEnabled;
  final LoopMode repeatMode;
}

final sourcePlaybackPresetsNotifier = ValueNotifier<Map<String, SourcePlaybackPreset>>(
  <String, SourcePlaybackPreset>{},
);

void _updateCurrentSourcePreset({bool? shuffle, LoopMode? repeat}) {
  final String type = currentPlaybackSourceTypeNotifier.value;
  final String name = currentPlaybackSourceNameNotifier.value;
  if (type.isEmpty || name.isEmpty) return;

  final sourceKey = '$type:$name';
  final map = Map<String, SourcePlaybackPreset>.from(sourcePlaybackPresetsNotifier.value);

  final SourcePlaybackPreset? currentPreset = map[sourceKey];
  final bool nextShuffle = shuffle ?? currentPreset?.shuffleEnabled ?? player.shuffleModeEnabled;
  final LoopMode nextRepeat = repeat ?? currentPreset?.repeatMode ?? queueRepeatModeNotifier.value;

  if (!nextShuffle && nextRepeat == LoopMode.off) {
    map.remove(sourceKey);
  } else {
    map[sourceKey] = SourcePlaybackPreset(
      shuffleEnabled: nextShuffle,
      repeatMode: nextRepeat,
    );
  }
  sourcePlaybackPresetsNotifier.value = map;
}

// 🔥 QUEUE
final currentIndexNotifier = ValueNotifier<int>(-1);
List<dynamic> globalQueue = [];
StreamSubscription<PlayerState>? _playerStateSubscription;
StreamSubscription<Duration?>? _durationSubscription;
StreamSubscription<Duration>? _positionSubscription;
Timer? _sleepTimer;
int _playRequestId = 0;
final math.Random _shuffleRandom = math.Random();
List<int> _shuffleOrder = <int>[];
List<dynamic>? _lastQueueReference;
bool _isAdvancingAfterCompletion = false;
bool _trackCompletionHandled = false;
bool _crossfadeInProgress = false;

double get _playbackVolumeTarget => volumeNormalizationEnabledNotifier.value ? 0.88 : 1.0;

AudioSource _buildAudioSource(String url, {MediaItem? tag}) {
  return AudioSource.uri(
    Uri.parse(url),
    headers: {
      'X-Emby-Token': apiKey,
      'X-Emby-Client': 'FlutterMusicApp',
      'X-Emby-Device': 'Android',
      'X-Emby-Device-Id': 'flutter-player',
      'X-Emby-Version': '1.0.0',
    },
    tag: tag,
  );
}

Future<bool> _setAudioSourceWithCandidates(
  AudioPlayer targetPlayer,
  String songId, {
  MediaItem? tag,
  Duration? initialPosition,
}) async {
  if (songId.isEmpty) return false;

  for (final String url in audioStreamUrlCandidates(songId)) {
    try {
      await targetPlayer.setAudioSource(
        _buildAudioSource(url, tag: tag),
        initialPosition: initialPosition,
      );
      if (await _hasPlayableDuration(targetPlayer)) {
        return true;
      }
    } catch (_) {}
  }
  return false;
}

Future<bool> _hasPlayableDuration(AudioPlayer targetPlayer) async {
  if (targetPlayer.processingState == ProcessingState.ready ||
      (targetPlayer.duration != null && targetPlayer.duration! > Duration.zero)) {
    return true;
  }

  try {
    await targetPlayer.processingStateStream
        .firstWhere(
          (ProcessingState state) =>
              state == ProcessingState.ready || state == ProcessingState.completed,
        )
        .timeout(const Duration(seconds: 8));
  } catch (_) {}

  return targetPlayer.processingState == ProcessingState.ready ||
      (targetPlayer.duration != null && targetPlayer.duration! > Duration.zero);
}

Future<void> _waitForPlayerReady(AudioPlayer targetPlayer) async {
  final ProcessingState state = targetPlayer.processingState;
  if (state == ProcessingState.ready) {
    return;
  }

  if (state == ProcessingState.loading || state == ProcessingState.buffering) {
    await targetPlayer.processingStateStream
        .firstWhere((ProcessingState next) => next == ProcessingState.ready)
        .timeout(const Duration(seconds: 25));
    return;
  }

  // After a track change the player can still report completed/idle briefly.
  // Wait for the newly loaded source to reach ready instead of resuming early.
  await targetPlayer.processingStateStream
      .firstWhere((ProcessingState next) => next == ProcessingState.ready)
      .timeout(const Duration(seconds: 25));
}

Future<void> _startPlayback() async {
  try {
    await _waitForPlayerReady(player);
  } catch (_) {}

  if (!player.playing) {
    unawaited(player.play());
    try {
      await player.playingStream
          .firstWhere((bool isPlaying) => isPlaying)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      if (!player.playing) {
        unawaited(player.play());
      }
    }
  }

  isPlayingNotifier.value = player.playing;
  _notifyBackgroundPlayback();
}

Future<void> applyVolumeNormalization() async {
  final double activeVolume = _crossfadeInProgress ? _crossfadePlayer.volume : player.volume;
  final double relativeVolume =
      _playbackVolumeTarget == 0 ? 1.0 : (activeVolume / _playbackVolumeTarget).clamp(0.0, 1.0);
  await _setActivePlaybackVolume(relativeVolume);
}

Future<void> _setActivePlaybackVolume(double relativeVolume) async {
  final double volume = (_playbackVolumeTarget * relativeVolume).clamp(0.0, 1.0);
  if (_crossfadeInProgress) {
    await _crossfadePlayer.setVolume(volume);
    return;
  }
  await player.setVolume(volume);
}

Future<void> _applyEqualizerTo(AndroidEqualizer equalizer) async {
  try {
    final AndroidEqualizerParameters parameters = await equalizer.parameters;
    final List<double> gains = equalizerGainsForPreset(
      equalizerPresetNotifier.value,
      parameters.bands.length,
    );

    for (var index = 0; index < parameters.bands.length; index++) {
      final double gain = gains[index].clamp(
        parameters.minDecibels,
        parameters.maxDecibels,
      );
      await parameters.bands[index].setGain(gain);
    }
    await equalizer.setEnabled(true);
  } catch (_) {}
}

Future<void> applyEqualizerSettings() async {
  await _applyEqualizerTo(mainEqualizer);
  await _applyEqualizerTo(crossfadeEqualizer);
}

Future<void> applyEqualizerPreset(EqualizerPreset preset) async {
  equalizerPresetNotifier.value = preset;
  if (preset != EqualizerPreset.custom) {
    try {
      final AndroidEqualizerParameters parameters = await mainEqualizer.parameters;
      storeCustomEqualizerGains(
        equalizerGainsForPreset(preset, parameters.bands.length),
      );
    } catch (_) {}
  }
  await applyEqualizerSettings();
}

Future<void> setCustomEqualizerBandGain(int bandIndex, double gain) async {
  equalizerPresetNotifier.value = EqualizerPreset.custom;

  try {
    final AndroidEqualizerParameters parameters = await mainEqualizer.parameters;
    final List<double> gains = equalizerGainsForPreset(
      EqualizerPreset.custom,
      parameters.bands.length,
    );
    while (gains.length <= bandIndex) {
      gains.add(0);
    }
    gains[bandIndex] = gain.clamp(parameters.minDecibels, parameters.maxDecibels);
    storeCustomEqualizerGains(gains);
  } catch (_) {
    final gains = List<double>.from(customEqualizerGainsNotifier.value);
    while (gains.length <= bandIndex) {
      gains.add(0);
    }
    gains[bandIndex] = gain;
    storeCustomEqualizerGains(gains);
  }

  for (final equalizer in <AndroidEqualizer>[
    mainEqualizer,
    crossfadeEqualizer,
  ]) {
    try {
      final AndroidEqualizerParameters parameters = await equalizer.parameters;
      final double clampedGain = gain.clamp(
        parameters.minDecibels,
        parameters.maxDecibels,
      );
      await parameters.bands[bandIndex].setGain(clampedGain);
      await equalizer.setEnabled(true);
    } catch (_) {}
  }
}

Future<void> initAudioPlayback() async {
  final AudioSession session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  _ensurePlayerStateBinding();
}

Future<void> _handleTrackCompletion() async {
  if (_isAdvancingAfterCompletion || _crossfadeInProgress) return;

  _isAdvancingAfterCompletion = true;
  try {
    if (queueRepeatModeNotifier.value == LoopMode.one) {
      await player.seek(Duration.zero);
      await _setActivePlaybackVolume(1.0);
      await player.play();
    } else {
      if (!gaplessPlaybackEnabledNotifier.value) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      await playNext();
    }
  } finally {
    _isAdvancingAfterCompletion = false;
    _trackCompletionHandled = false;
  }
}

void _onPositionUpdate(Duration position) {
  currentPositionNotifier.value = position;
  if (currentIndexNotifier.value >= 0 && _playbackPrefs != null) {
    _playbackPrefs!.setInt('saved_song_position_ms', position.inMilliseconds);
  }
  if (!player.playing || _isAdvancingAfterCompletion || _crossfadeInProgress) return;

  final Duration duration = player.duration ?? currentDurationNotifier.value;
  if (duration <= Duration.zero) return;

  final Duration remaining = duration - position;
  final int crossfadeSeconds = crossfadeSecondsNotifier.value.round();
  final crossfadeDuration = Duration(seconds: crossfadeSeconds);

  if (crossfadeSeconds > 0 && remaining <= crossfadeDuration) {
    if (!_trackCompletionHandled) {
      _trackCompletionHandled = true;
      unawaited(_beginCrossfadeToNext(crossfadeDuration));
    }
    return;
  }

  final completionThreshold = gaplessPlaybackEnabledNotifier.value
      ? const Duration(milliseconds: 350)
      : const Duration(milliseconds: 900);

  if (remaining > completionThreshold) {
    _trackCompletionHandled = false;
    return;
  }

  if (_trackCompletionHandled) return;

  if (player.processingState == ProcessingState.completed || remaining <= completionThreshold) {
    _trackCompletionHandled = true;
    unawaited(_handleTrackCompletion());
  }
}

void _abortCrossfade() {
  if (_crossfadeInProgress) {
    _crossfadeInProgress = false;
    unawaited(_crossfadePlayer.stop());
  }
}

Future<void> _beginCrossfadeToNext(Duration crossfadeDuration) async {
  if (_crossfadeInProgress || _isAdvancingAfterCompletion) return;

  if (queueRepeatModeNotifier.value == LoopMode.one) {
    await _handleTrackCompletion();
    return;
  }

  final int nextIndex = _nextQueueIndex(currentIndexNotifier.value);
  if (nextIndex == -1) {
    _trackCompletionHandled = false;
    return;
  }

  final dynamic nextSong = globalQueue[nextIndex];
  final String nextId = _songId(nextSong);
  if (nextId.isEmpty) {
    _trackCompletionHandled = false;
    return;
  }

  _crossfadeInProgress = true;
  try {
    final bool loaded = await _setAudioSourceWithCandidates(_crossfadePlayer, nextId);
    if (!_crossfadeInProgress) {
      unawaited(_crossfadePlayer.stop());
      return;
    }
    if (!loaded) {
      _trackCompletionHandled = false;
      if (player.processingState == ProcessingState.completed) {
        _trackCompletionHandled = true;
        unawaited(_handleTrackCompletion());
      }
      return;
    }
    await _crossfadePlayer.setVolume(0);
    if (!_crossfadeInProgress) {
      unawaited(_crossfadePlayer.stop());
      return;
    }
    await _crossfadePlayer.play();
    if (!_crossfadeInProgress) {
      unawaited(_crossfadePlayer.stop());
      return;
    }

    const steps = 24;
    final int stepMs = (crossfadeDuration.inMilliseconds / steps).round().clamp(1, 1000);
    for (var step = 1; step <= steps; step++) {
      if (!_crossfadeInProgress) break;
      final double progress = step / steps;
      await player.setVolume(_playbackVolumeTarget * (1 - progress));
      await _crossfadePlayer.setVolume(_playbackVolumeTarget * progress);
      await Future<void>.delayed(Duration(milliseconds: stepMs));
    }

    if (!_crossfadeInProgress) {
      unawaited(player.setVolume(_playbackVolumeTarget));
      unawaited(_crossfadePlayer.stop());
      return;
    }

    final Duration incomingPosition = _crossfadePlayer.position;
    await player.stop();
    await _crossfadePlayer.stop();

    if (!_crossfadeInProgress) {
      unawaited(player.setVolume(_playbackVolumeTarget));
      return;
    }

    await playSong(
      getAudioUrl(nextId),
      title: _songTitle(nextSong),
      image: getImageUrl(nextId),
      artist: _songArtist(nextSong),
      index: nextIndex,
      queue: globalQueue,
      trackDuration: durationFromTicks(nextSong['RunTimeTicks']),
      playbackSourceType: currentPlaybackSourceTypeNotifier.value,
      playbackSourceName: currentPlaybackSourceNameNotifier.value,
      isCrossfadeTransition: true,
    );
    if (incomingPosition > Duration.zero) {
      await player.seek(incomingPosition);
    }
    await _setActivePlaybackVolume(1.0);
  } catch (e) {
    print('CROSSFADE ERROR: $e');
    unawaited(_crossfadePlayer.stop());
    if (_crossfadeInProgress) {
      await playNext();
    }
  } finally {
    _crossfadeInProgress = false;
    _trackCompletionHandled = false;
  }
}

void _ensurePlayerStateBinding() {
  _playerStateSubscription ??= player.playerStateStream.listen((state) {
    isPlayingNotifier.value = state.playing;
    _notifyBackgroundPlayback();
    if (state.processingState != ProcessingState.completed || _isAdvancingAfterCompletion) {
      return;
    }

    if (_trackCompletionHandled) return;
    _trackCompletionHandled = true;
    unawaited(_handleTrackCompletion());
  });
  _durationSubscription ??= player.durationStream.listen((duration) {
    if (duration != null && duration > Duration.zero) {
      currentDurationNotifier.value = duration;
    }
  });
  _positionSubscription ??= player.positionStream.listen(_onPositionUpdate);
}

Duration durationFromTicks(dynamic ticks) {
  if (ticks is num && ticks > 0) {
    return Duration(microseconds: (ticks / 10).round());
  }
  return Duration.zero;
}

Future<void> playSong(
  String url, {
  required String title,
  required String image,
  required String artist,
  required int index,
  required List<dynamic> queue,
  Duration? trackDuration,
  String? playbackSourceType,
  String? playbackSourceName,
  bool autoPlay = true,
  Duration? resumePosition,
  bool isCrossfadeTransition = false,
}) async {
  if (!isCrossfadeTransition) {
    _abortCrossfade();
  }
  _ensurePlayerStateBinding();
  await ensureBackgroundAudioService?.call();
  final int requestId = ++_playRequestId;
  _trackCompletionHandled = false;
  final preservePosition = resumePosition != null;
  globalQueue = queue;
  _syncQueueReference(queue, index);
  _ensureShuffleOrder(index);
  _notifyQueueChanged();
  currentPositionNotifier.value = preservePosition ? resumePosition : Duration.zero;
  currentDurationNotifier.value = trackDuration ?? Duration.zero;

  try {
    await player.pause();
    if (!preservePosition) {
      await player.seek(Duration.zero);
    }
    if (requestId != _playRequestId) return;

    currentIndexNotifier.value = index;
    currentSongIdNotifier.value = index >= 0 && index < queue.length ? _songId(queue[index]) : '';
    currentImageNotifier.value = image;
    currentArtistNotifier.value = artist;
    currentSongNotifier.value = title;
    final _PlaybackSource playbackSource = _resolvePlaybackSource(
      index: index,
      queue: queue,
      playbackSourceType: playbackSourceType,
      playbackSourceName: playbackSourceName,
    );
    currentPlaybackSourceTypeNotifier.value = playbackSource.type;
    currentPlaybackSourceNameNotifier.value = playbackSource.name;
    currentTrackRevisionNotifier.value++;

    final sourceKey = '${playbackSource.type}:${playbackSource.name}';
    if (playbackSource.type.isNotEmpty && playbackSource.name.isNotEmpty) {
      final SourcePlaybackPreset? preset = sourcePlaybackPresetsNotifier.value[sourceKey];
      if (preset != null) {
        await player.setShuffleModeEnabled(preset.shuffleEnabled);
        if (preset.shuffleEnabled) {
          _regenerateShuffleOrder(index);
        }
        queueRepeatModeNotifier.value = preset.repeatMode;
      } else {
        await player.setShuffleModeEnabled(false);
        queueRepeatModeNotifier.value = LoopMode.off;
      }
    } else {
      await player.setShuffleModeEnabled(false);
      queueRepeatModeNotifier.value = LoopMode.off;
    }

    final String songId = index >= 0 && index < queue.length ? _songId(queue[index]) : '';
    final String albumLabel = playbackSource.name.isNotEmpty ? playbackSource.name : artist;
    final mediaItem = MediaItem(
      id: songId.isNotEmpty ? songId : url,
      title: title,
      artist: artist,
      album: albumLabel,
      artUri: image.isNotEmpty ? Uri.parse(image) : null,
      duration: trackDuration,
    );
    updateBackgroundMediaItem?.call(
      id: mediaItem.id,
      title: title,
      artist: artist,
      album: albumLabel,
      imageUrl: image,
      duration: trackDuration,
    );
    var loaded = false;
    if (songId.isNotEmpty) {
      loaded = await _setAudioSourceWithCandidates(
        player,
        songId,
        tag: mediaItem,
        initialPosition: resumePosition,
      );
    }
    if (!loaded && url.isNotEmpty) {
      try {
        await player.setAudioSource(
          _buildAudioSource(url, tag: mediaItem),
          initialPosition: resumePosition,
        );
        loaded = true;
      } catch (e) {
        print('PLAY ERROR: $e');
        return;
      }
    }
    if (!loaded) {
      print('PLAY ERROR: No playable stream found');
      return;
    }
    if (requestId != _playRequestId) return;

    if (index >= 0 && index < queue.length) {
      recordRecentPlayback(queue[index]);
    }

    await _setActivePlaybackVolume(1.0);

    if (preservePosition && resumePosition > Duration.zero) {
      try {
        await _waitForPlayerReady(player);
        final Duration? duration = player.duration;
        final Duration target = duration != null && duration > Duration.zero
            ? Duration(
                milliseconds: resumePosition.inMilliseconds.clamp(
                  0,
                  duration.inMilliseconds,
                ),
              )
            : resumePosition;
        await player.seek(target);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if ((player.position - target).abs() > const Duration(seconds: 2)) {
          await player.seek(target);
        }
        currentPositionNotifier.value = player.position;
      } catch (_) {}
    }

    if (autoPlay) {
      await _startPlayback();
    } else {
      isPlayingNotifier.value = false;
      _notifyBackgroundPlayback();
    }
    unawaited(savePlaybackState());
    unawaited(applyEqualizerSettings());
  } catch (e) {
    print('PLAY ERROR: $e');
  }
}

Future<void> playNext() async {
  if (queueRepeatModeNotifier.value == LoopMode.one) {
    await setQueueRepeatMode(LoopMode.off);
  }

  final int index = currentIndexNotifier.value;

  if (globalQueue.isEmpty) return;

  final int nextIndex = _nextQueueIndex(index);
  if (nextIndex == -1) return;

  final next = globalQueue[nextIndex];
  final String nextId = _songId(next);
  if (nextId.isEmpty) return;

  await playSong(
    getAudioUrl(nextId),
    title: _songTitle(next),
    image: getImageUrl(nextId),
    artist: _songArtist(next),
    index: nextIndex,
    queue: globalQueue,
    trackDuration: durationFromTicks(next['RunTimeTicks']),
    playbackSourceType: currentPlaybackSourceTypeNotifier.value,
    playbackSourceName: currentPlaybackSourceNameNotifier.value,
  );
}

Future<void> playPrev() async {
  if (queueRepeatModeNotifier.value == LoopMode.one) {
    await setQueueRepeatMode(LoopMode.off);
  }

  final int index = currentIndexNotifier.value;

  if (globalQueue.isEmpty) return;

  final int previousIndex = _previousQueueIndex(index);
  if (previousIndex == -1) return;

  final prev = globalQueue[previousIndex];
  final String prevId = _songId(prev);
  if (prevId.isEmpty) return;

  await playSong(
    getAudioUrl(prevId),
    title: _songTitle(prev),
    image: getImageUrl(prevId),
    artist: _songArtist(prev),
    index: previousIndex,
    queue: globalQueue,
    trackDuration: durationFromTicks(prev['RunTimeTicks']),
    playbackSourceType: currentPlaybackSourceTypeNotifier.value,
    playbackSourceName: currentPlaybackSourceNameNotifier.value,
  );
}

int _nextQueueIndex(int currentIndex) {
  if (globalQueue.isEmpty) return -1;

  if (player.shuffleModeEnabled && globalQueue.length > 1) {
    _ensureShuffleOrder(currentIndex);
    final int currentOrderIndex = _shuffleOrder.indexOf(currentIndex);
    if (currentOrderIndex == -1) {
      return _shuffleOrder.isEmpty ? -1 : _shuffleOrder.first;
    }

    if (currentOrderIndex < _shuffleOrder.length - 1) {
      return _shuffleOrder[currentOrderIndex + 1];
    }

    if (queueRepeatModeNotifier.value == LoopMode.all) {
      _regenerateShuffleOrder(currentIndex);
      if (_shuffleOrder.length > 1) {
        return _shuffleOrder[1];
      }
      return _shuffleOrder.isEmpty ? -1 : _shuffleOrder.first;
    }

    return -1;
  }

  if (currentIndex < globalQueue.length - 1) {
    return currentIndex + 1;
  }

  if (queueRepeatModeNotifier.value == LoopMode.all) {
    return 0;
  }

  return -1;
}

int _previousQueueIndex(int currentIndex) {
  if (globalQueue.isEmpty) return -1;

  if (player.shuffleModeEnabled) {
    _ensureShuffleOrder(currentIndex);
    final int currentOrderIndex = _shuffleOrder.indexOf(currentIndex);
    if (currentOrderIndex > 0) {
      return _shuffleOrder[currentOrderIndex - 1];
    }
    if (queueRepeatModeNotifier.value == LoopMode.all && _shuffleOrder.isNotEmpty) {
      return _shuffleOrder.last;
    }
    return -1;
  }

  if (currentIndex > 0) {
    return currentIndex - 1;
  }

  if (queueRepeatModeNotifier.value == LoopMode.all) {
    return globalQueue.length - 1;
  }

  return -1;
}

Future<void> setShuffleEnabled(bool enabled) async {
  await player.setShuffleModeEnabled(enabled);
  if (enabled) {
    _regenerateShuffleOrder(currentIndexNotifier.value);
  }
  _updateCurrentSourcePreset(shuffle: enabled);
  _notifyQueueChanged();
  _notifyBackgroundPlayback();
}

Future<void> setQueueRepeatMode(LoopMode mode) async {
  queueRepeatModeNotifier.value = mode;
  await player.setLoopMode(LoopMode.off);
  _updateCurrentSourcePreset(repeat: mode);
  _notifyQueueChanged();
  _notifyBackgroundPlayback();
}

void setSleepTimer(Duration duration) {
  _sleepTimer?.cancel();
  sleepTimerEndsAtNotifier.value = DateTime.now().add(duration);
  _sleepTimer = Timer(duration, () async {
    await player.pause();
    sleepTimerEndsAtNotifier.value = null;
    _sleepTimer = null;
  });
}

void cancelSleepTimer() {
  _sleepTimer?.cancel();
  _sleepTimer = null;
  sleepTimerEndsAtNotifier.value = null;
}

Future<void> stopPlayback() async {
  _abortCrossfade();
  final int requestId = ++_playRequestId;
  await player.stop();
  if (requestId != _playRequestId) return;

  _notifyBackgroundPlayback();

  // Clear saved playback state
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('saved_song_active', false);
  } catch (_) {}

  globalQueue = <dynamic>[];
  _shuffleOrder = <int>[];
  _lastQueueReference = null;
  currentIndexNotifier.value = -1;
  currentSongIdNotifier.value = '';
  currentSongNotifier.value = 'Nothing playing';
  currentPlaybackSourceTypeNotifier.value = '';
  currentPlaybackSourceNameNotifier.value = '';
  currentImageNotifier.value = '';
  currentArtistNotifier.value = 'Unknown';
  currentPositionNotifier.value = Duration.zero;
  currentDurationNotifier.value = Duration.zero;
  currentTrackRevisionNotifier.value++;
  _notifyQueueChanged();
}

void syncQueueWithPlaylistSongs(List<dynamic> songs, String playlistName) {
  if (currentPlaybackSourceTypeNotifier.value != 'Playlist') return;
  if (currentPlaybackSourceNameNotifier.value != playlistName) return;

  final int previousIndex = currentIndexNotifier.value;
  final String? currentSongId = previousIndex >= 0 && previousIndex < globalQueue.length
      ? _songId(globalQueue[previousIndex])
      : null;

  globalQueue = List<dynamic>.from(songs);
  _lastQueueReference = globalQueue;

  if (globalQueue.isEmpty) {
    unawaited(stopPlayback());
    return;
  }

  var nextIndex = 0;
  if (currentSongId != null && currentSongId.isNotEmpty) {
    final int matchedIndex = globalQueue.indexWhere((song) => _songId(song) == currentSongId);
    if (matchedIndex >= 0) {
      nextIndex = matchedIndex;
    } else if (previousIndex >= 0) {
      nextIndex = previousIndex.clamp(0, globalQueue.length - 1);
    }
  }

  currentIndexNotifier.value = nextIndex;
  if (player.shuffleModeEnabled) {
    _regenerateShuffleOrder(nextIndex);
  }
  _notifyQueueChanged();
}

List<dynamic> upcomingQueueSnapshot() {
  if (globalQueue.isEmpty) return <dynamic>[];

  return _upcomingQueueIndices().map((index) {
    return globalQueue[index];
  }).toList();
}

void addSongToQueue(dynamic song) {
  if (song == null) return;
  final bool wasShuffleEnabled = player.shuffleModeEnabled;
  if (wasShuffleEnabled) {
    _ensureShuffleOrder(currentIndexNotifier.value);
  }
  final int addedIndex = globalQueue.length;
  globalQueue = List<dynamic>.from(globalQueue)..add(song);
  _lastQueueReference = globalQueue;
  if (wasShuffleEnabled) {
    if (addedIndex != currentIndexNotifier.value) {
      _shuffleOrder = <int>[..._shuffleOrder, addedIndex];
    }
  } else {
    _regenerateShuffleOrder(currentIndexNotifier.value);
  }
  _notifyQueueChanged();
}

void removeUpcomingQueueItem(int upcomingIndex) {
  final int queueIndex = _queueIndexForUpcomingIndex(upcomingIndex);
  if (queueIndex == -1 || queueIndex == currentIndexNotifier.value) return;

  globalQueue = List<dynamic>.from(globalQueue)..removeAt(queueIndex);
  _lastQueueReference = globalQueue;

  final int currentIndex = currentIndexNotifier.value;
  final bool wasShuffleEnabled = player.shuffleModeEnabled;
  if (queueIndex < currentIndex) {
    currentIndexNotifier.value = currentIndex - 1;
  }

  if (wasShuffleEnabled) {
    _shuffleOrder = _shuffleOrder
        .where((index) => index != queueIndex)
        .map((index) => index > queueIndex ? index - 1 : index)
        .toList();
    _ensureShuffleOrder(currentIndexNotifier.value);
  } else {
    _regenerateShuffleOrder(currentIndexNotifier.value);
  }
  _notifyQueueChanged();
}

void moveUpcomingQueueItem(int oldUpcomingIndex, int newUpcomingIndex) {
  if (oldUpcomingIndex == newUpcomingIndex) return;

  if (player.shuffleModeEnabled) {
    _ensureShuffleOrder(currentIndexNotifier.value);
    final List<int> upcomingIndices = _upcomingQueueIndices();
    if (oldUpcomingIndex < 0 ||
        oldUpcomingIndex >= upcomingIndices.length ||
        newUpcomingIndex < 0 ||
        newUpcomingIndex > upcomingIndices.length) {
      return;
    }
    if (newUpcomingIndex > oldUpcomingIndex) newUpcomingIndex -= 1;

    final int movedIndex = upcomingIndices.removeAt(oldUpcomingIndex);
    upcomingIndices.insert(newUpcomingIndex, movedIndex);
    final int currentIndex = currentIndexNotifier.value;
    final int currentOrderIndex = _shuffleOrder.indexOf(currentIndex);
    _shuffleOrder = <int>[
      if (currentOrderIndex >= 0) ..._shuffleOrder.take(currentOrderIndex + 1),
      ...upcomingIndices,
    ];
    _notifyQueueChanged();
    return;
  }

  final int currentIndex = currentIndexNotifier.value;
  if (currentIndex < 0) return;

  final int oldQueueIndex = currentIndex + 1 + oldUpcomingIndex;
  int newQueueIndex = currentIndex + 1 + newUpcomingIndex;
  if (oldQueueIndex < 0 ||
      oldQueueIndex >= globalQueue.length ||
      newQueueIndex < currentIndex + 1 ||
      newQueueIndex > globalQueue.length) {
    return;
  }
  if (newQueueIndex > oldQueueIndex) newQueueIndex -= 1;

  final nextQueue = List<dynamic>.from(globalQueue);
  final dynamic movedSong = nextQueue.removeAt(oldQueueIndex);
  nextQueue.insert(newQueueIndex, movedSong);
  globalQueue = nextQueue;
  _lastQueueReference = globalQueue;
  _regenerateShuffleOrder(currentIndex);
  _notifyQueueChanged();
}

void _syncQueueReference(List<dynamic> queue, int index) {
  if (!identical(_lastQueueReference, queue)) {
    _lastQueueReference = queue;
    _regenerateShuffleOrder(index);
  }
}

void _ensureShuffleOrder(int currentIndex) {
  final Set<int> orderSet = _shuffleOrder.toSet();
  final bool hasEveryQueueIndex = orderSet.length == globalQueue.length &&
      List<int>.generate(globalQueue.length, (index) => index).every(orderSet.contains);

  if (_shuffleOrder.length != globalQueue.length || !hasEveryQueueIndex) {
    _regenerateShuffleOrder(currentIndex);
  }
}

void _regenerateShuffleOrder(int currentIndex) {
  final remainingIndices = <int>[
    for (var i = 0; i < globalQueue.length; i++)
      if (i != currentIndex) i,
  ]..shuffle(_shuffleRandom);

  _shuffleOrder = <int>[
    if (currentIndex >= 0 && currentIndex < globalQueue.length) currentIndex,
    ...remainingIndices,
  ];
}

List<int> _upcomingQueueIndices() {
  final int currentIndex = currentIndexNotifier.value;
  if (player.shuffleModeEnabled) {
    _ensureShuffleOrder(currentIndex);
    final int currentOrderIndex = _shuffleOrder.indexOf(currentIndex);
    if (currentOrderIndex == -1) return List<int>.from(_shuffleOrder);
    final List<int> upcomingIndices = _shuffleOrder.skip(currentOrderIndex + 1).toList();
    if (upcomingIndices.isEmpty && queueRepeatModeNotifier.value == LoopMode.all) {
      return _shuffleOrder.where((index) => index != currentIndex).toList();
    }
    return upcomingIndices;
  }

  if (currentIndex < 0) {
    return <int>[for (var i = 0; i < globalQueue.length; i++) i];
  }

  final upcomingIndices = <int>[
    for (var i = currentIndex + 1; i < globalQueue.length; i++) i,
  ];
  if (upcomingIndices.isEmpty && queueRepeatModeNotifier.value == LoopMode.all) {
    return <int>[for (var i = 0; i < globalQueue.length; i++) i];
  }
  return upcomingIndices;
}

int _queueIndexForUpcomingIndex(int upcomingIndex) {
  final List<int> upcomingIndices = _upcomingQueueIndices();
  if (upcomingIndex < 0 || upcomingIndex >= upcomingIndices.length) {
    return -1;
  }
  return upcomingIndices[upcomingIndex];
}

void _notifyQueueChanged() {
  queueRevisionNotifier.value++;
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

_PlaybackSource _resolvePlaybackSource({
  required int index,
  required List<dynamic> queue,
  String? playbackSourceType,
  String? playbackSourceName,
}) {
  final String cleanType = playbackSourceType?.trim() ?? '';
  final String cleanName = playbackSourceName?.trim() ?? '';
  if (cleanType.isNotEmpty && cleanName.isNotEmpty) {
    return _PlaybackSource(cleanType, cleanName);
  }

  if (index >= 0 && index < queue.length) {
    final dynamic song = queue[index];
    if (song is Map && song['_PlayedFromAlbum'] == true) {
      final String album = song['Album']?.toString() ?? '';
      if (album.isNotEmpty) return _PlaybackSource('Album', album);
    }
  }

  return const _PlaybackSource('', '');
}

class _PlaybackSource {
  const _PlaybackSource(this.type, this.name);

  final String type;
  final String name;
}

Future<void> pausePlayback() async {
  _abortCrossfade();
  await player.pause();
  _notifyBackgroundPlayback();
  unawaited(savePlaybackState());
}

Future<void> resumePlayback() async {
  _abortCrossfade();
  await player.play();
  _notifyBackgroundPlayback();
  unawaited(savePlaybackState());
}

void togglePlayPause() {
  _ensurePlayerStateBinding();
  _abortCrossfade();
  if (player.playing) {
    player.pause();
  } else {
    player.play();
  }
  _notifyBackgroundPlayback();
  unawaited(savePlaybackState());
}

SharedPreferences? _playbackPrefs;

Future<void> _initPlaybackPrefs() async {
  _playbackPrefs ??= await SharedPreferences.getInstance();
}

Future<void> savePlaybackState() async {
  try {
    await _initPlaybackPrefs();
    final SharedPreferences prefs = _playbackPrefs!;
    final int index = currentIndexNotifier.value;
    if (index >= 0 && index < globalQueue.length) {
      final dynamic song = globalQueue[index];
      final String songId = _songId(song);
      await prefs.setBool('saved_song_active', true);
      await prefs.setString('saved_song_url', getAudioUrl(songId));
      await prefs.setString('saved_song_title', currentSongNotifier.value);
      await prefs.setString('saved_song_image', currentImageNotifier.value);
      await prefs.setString('saved_song_artist', currentArtistNotifier.value);
      await prefs.setInt('saved_song_index', index);
      await prefs.setString('saved_song_queue', json.encode(globalQueue));
      await prefs.setString('saved_song_source_type', currentPlaybackSourceTypeNotifier.value);
      await prefs.setString('saved_song_source_name', currentPlaybackSourceNameNotifier.value);
      await prefs.setInt('saved_song_position_ms', currentPositionNotifier.value.inMilliseconds);
      await prefs.setInt('saved_song_duration_ms', currentDurationNotifier.value.inMilliseconds);
    } else {
      await prefs.setBool('saved_song_active', false);
    }
  } catch (e) {
    print('SAVE PLAYBACK ERROR: $e');
  }
}

Future<void> restorePlaybackState() async {
  try {
    await _initPlaybackPrefs();
    final SharedPreferences prefs = _playbackPrefs!;
    final bool? active = prefs.getBool('saved_song_active');
    if (active != true) return;

    final String url = prefs.getString('saved_song_url') ?? '';
    final String title = prefs.getString('saved_song_title') ?? '';
    final String image = prefs.getString('saved_song_image') ?? '';
    final String artist = prefs.getString('saved_song_artist') ?? '';
    final int index = prefs.getInt('saved_song_index') ?? -1;
    final String queueStr = prefs.getString('saved_song_queue') ?? '[]';
    final String sourceType = prefs.getString('saved_song_source_type') ?? '';
    final String sourceName = prefs.getString('saved_song_source_name') ?? '';
    final int positionMs = prefs.getInt('saved_song_position_ms') ?? 0;
    final int durationMs = prefs.getInt('saved_song_duration_ms') ?? 0;

    if (url.isEmpty || title.isEmpty || index == -1) return;

    final queue = json.decode(queueStr) as List<dynamic>;

    await playSong(
      url,
      title: title,
      image: image,
      artist: artist,
      index: index,
      queue: queue,
      trackDuration: Duration(milliseconds: durationMs),
      playbackSourceType: sourceType,
      playbackSourceName: sourceName,
      autoPlay: false,
      resumePosition: Duration(milliseconds: positionMs),
    );
  } catch (e) {
    print('RESTORE PLAYBACK ERROR: $e');
  }
}
