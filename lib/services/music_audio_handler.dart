import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_service.dart' as playback;

class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicAudioHandler() {
    playback.player.playbackEventStream.listen((_) => syncPlaybackState());
    playback.player.playerStateStream.listen((_) => syncPlaybackState());
    playback.player.shuffleModeEnabledStream.listen((_) => syncPlaybackState());
    playback.queueRepeatModeNotifier.addListener(syncPlaybackState);
    playback.player.positionStream.listen((_) {
      if (playback.player.playing) {
        syncPlaybackState();
      }
    });
  }

  void attach() {
    playback.syncBackgroundNotification = syncPlaybackState;
    playback.updateBackgroundMediaItem = updateNowPlaying;
    syncPlaybackState();
  }

  void updateNowPlaying({
    required String id,
    required String title,
    required String artist,
    required String album,
    String? imageUrl,
    Duration? duration,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        artUri: imageUrl != null && imageUrl.isNotEmpty ? Uri.parse(imageUrl) : null,
        duration: duration,
      ),
    );
    syncPlaybackState();
  }

  void syncPlaybackState() {
    final bool isPlaying = playing;
    final List<MediaControl> controls = _notificationControls(isPlaying);

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        androidCompactActionIndices: _compactActionIndices(controls),
        systemActions: const <MediaAction>{
          MediaAction.seek,
        },
        processingState: _mapProcessingState(playback.player.processingState),
        playing: isPlaying,
        updatePosition: playback.player.position,
        bufferedPosition: playback.player.bufferedPosition,
        speed: playback.player.speed,
        queueIndex: playback.currentIndexNotifier.value >= 0
            ? playback.currentIndexNotifier.value
            : null,
        repeatMode: _mapRepeatMode(playback.queueRepeatModeNotifier.value),
        shuffleMode: playback.player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  /// Only standard transport controls belong in compact indices. Custom
  /// shuffle/repeat actions are session actions (Android 13+) and must not be
  /// referenced on API levels where compact indices map to notification actions.
  List<int> _compactActionIndices(List<MediaControl> controls) {
    final nativeIndices = <int>[
      for (int i = 0; i < controls.length; i++)
        if (controls[i].action != MediaAction.custom) i,
    ];
    return nativeIndices.take(3).toList();
  }

  List<MediaControl> _notificationControls(bool isPlaying) {
    return <MediaControl>[
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.custom(
        androidIcon: playback.player.shuffleModeEnabled
            ? 'drawable/ic_notification_shuffle_on'
            : 'drawable/ic_notification_shuffle_off',
        label: 'Shuffle',
        name: 'toggle_shuffle',
      ),
      MediaControl.custom(
        androidIcon: _repeatIconName(),
        label: 'Repeat',
        name: 'toggle_repeat',
      ),
    ];
  }

  bool get playing =>
      playback.player.playing &&
      playback.player.processingState != ProcessingState.completed &&
      playback.player.processingState != ProcessingState.idle;

  String _repeatIconName() {
    switch (playback.queueRepeatModeNotifier.value) {
      case LoopMode.one:
        return 'drawable/ic_notification_repeat_one';
      case LoopMode.all:
        return 'drawable/ic_notification_repeat_on';
      case LoopMode.off:
        return 'drawable/ic_notification_repeat_off';
    }
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  AudioServiceRepeatMode _mapRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
    }
  }

  LoopMode _nextRepeatMode() {
    switch (playback.queueRepeatModeNotifier.value) {
      case LoopMode.off:
        return LoopMode.all;
      case LoopMode.all:
        return LoopMode.one;
      case LoopMode.one:
        return LoopMode.off;
    }
  }

  @override
  Future<void> play() async {
    await playback.resumePlayback();
    syncPlaybackState();
  }

  @override
  Future<void> pause() async {
    await playback.pausePlayback();
    syncPlaybackState();
  }

  @override
  Future<void> stop() async {
    await playback.stopPlayback();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => playback.player.seek(position);

  @override
  Future<void> skipToNext() => playback.playNext();

  @override
  Future<void> skipToPrevious() => playback.playPrev();

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await playback.setShuffleEnabled(shuffleMode != AudioServiceShuffleMode.none);
    syncPlaybackState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final LoopMode mode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await playback.setQueueRepeatMode(mode);
    syncPlaybackState();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggle_shuffle':
        await playback.setShuffleEnabled(!playback.player.shuffleModeEnabled);
      case 'toggle_repeat':
        await playback.setQueueRepeatMode(_nextRepeatMode());
    }
    syncPlaybackState();
  }
}

Future<MusicAudioHandler>? _musicAudioHandlerFuture;

Future<MusicAudioHandler> ensureMusicAudioService() {
  return _musicAudioHandlerFuture ??= initMusicAudioService();
}

Future<MusicAudioHandler> initMusicAudioService() async {
  final MusicAudioHandler handler = await AudioService.init(
    builder: () => MusicAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_app.audio',
      androidNotificationChannelName: 'Music playback',
      androidStopForegroundOnPause: false,
    ),
  );
  handler.attach();
  return handler;
}
