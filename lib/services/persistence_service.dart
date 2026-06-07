import 'dart:convert';

import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_preferences_settings.dart';
import 'audio_service.dart';
import 'equalizer_settings.dart';
import 'library_activity_log.dart';
import 'library_state.dart';
import 'sleep_timer_settings.dart';
import 'theme_state.dart';

late final SharedPreferences _prefs;

// Helper function to extract enum names in a way that is compatible with all
// Dart versions and avoids static analyzer warnings in IDEs.
String _enumName(dynamic enumValue) {
  return enumValue.toString().split('.').last;
}

Future<void> initPersistence() async {
  _prefs = await SharedPreferences.getInstance();

  // 1. Theme Choice
  final String? themeChoiceStr = _prefs.getString('theme_choice');
  if (themeChoiceStr != null) {
    try {
      appThemeChoiceNotifier.value = AppThemeChoice.values.firstWhere(
        (e) => _enumName(e) == themeChoiceStr,
        orElse: () => AppThemeChoice.systemDefault,
      );
    } catch (_) {}
  }
  appThemeChoiceNotifier.addListener(() {
    _prefs.setString('theme_choice', _enumName(appThemeChoiceNotifier.value));
  });

  // 2. Volume Normalization
  final bool? volumeNorm = _prefs.getBool('volume_normalization');
  if (volumeNorm != null) {
    volumeNormalizationEnabledNotifier.value = volumeNorm;
  }
  volumeNormalizationEnabledNotifier.addListener(() {
    _prefs.setBool('volume_normalization', volumeNormalizationEnabledNotifier.value);
  });

  // 3. Crossfade Seconds
  final double? crossfadeSec = _prefs.getDouble('crossfade_seconds');
  if (crossfadeSec != null) {
    crossfadeSecondsNotifier.value = crossfadeSec;
  }
  crossfadeSecondsNotifier.addListener(() {
    _prefs.setDouble('crossfade_seconds', crossfadeSecondsNotifier.value);
  });

  // 4. Gapless Playback
  final bool? gapless = _prefs.getBool('gapless_playback');
  if (gapless != null) {
    gaplessPlaybackEnabledNotifier.value = gapless;
  }
  gaplessPlaybackEnabledNotifier.addListener(() {
    _prefs.setBool('gapless_playback', gaplessPlaybackEnabledNotifier.value);
  });

  // 5. Equalizer Preset
  final String? eqPresetStr = _prefs.getString('equalizer_preset');
  if (eqPresetStr != null) {
    try {
      equalizerPresetNotifier.value = EqualizerPreset.values.firstWhere(
        (e) => _enumName(e) == eqPresetStr,
        orElse: () => EqualizerPreset.balanced,
      );
    } catch (_) {}
  }
  equalizerPresetNotifier.addListener(() {
    _prefs.setString('equalizer_preset', _enumName(equalizerPresetNotifier.value));
  });

  // 6. Custom Equalizer Gains
  final String? eqGainsStr = _prefs.getString('equalizer_gains');
  if (eqGainsStr != null) {
    try {
      final list = json.decode(eqGainsStr) as List<dynamic>;
      customEqualizerGainsNotifier.value = list.map((item) => (item as num).toDouble()).toList();
    } catch (_) {}
  }
  customEqualizerGainsNotifier.addListener(() {
    _prefs.setString('equalizer_gains', json.encode(customEqualizerGainsNotifier.value));
  });

  // 7. Sleep Timer Preset Count
  final int? sleepCount = _prefs.getInt('sleep_timer_preset_count');
  if (sleepCount != null) {
    sleepTimerPresetCountNotifier.value = sleepCount;
  }
  sleepTimerPresetCountNotifier.addListener(() {
    _prefs.setInt('sleep_timer_preset_count', sleepTimerPresetCountNotifier.value);
  });

  // 8. Sleep Timer Preset Minutes
  final String? sleepMinStr = _prefs.getString('sleep_timer_preset_minutes');
  if (sleepMinStr != null) {
    try {
      final list = json.decode(sleepMinStr) as List<dynamic>;
      sleepTimerPresetMinutesNotifier.value = list.map((item) => (item as num).toInt()).toList();
    } catch (_) {}
  }
  sleepTimerPresetMinutesNotifier.addListener(() {
    _prefs.setString('sleep_timer_preset_minutes', json.encode(sleepTimerPresetMinutesNotifier.value));
  });

  // 9. Sleep Timer Custom Enabled
  final bool? sleepCustom = _prefs.getBool('sleep_timer_custom_enabled');
  if (sleepCustom != null) {
    sleepTimerCustomEnabledNotifier.value = sleepCustom;
  }
  sleepTimerCustomEnabledNotifier.addListener(() {
    _prefs.setBool('sleep_timer_custom_enabled', sleepTimerCustomEnabledNotifier.value);
  });

  // 10. Library Activity Log (Refreshed every 24 hours)
  final String? logStr = _prefs.getString('library_activity_log');
  if (logStr != null) {
    try {
      final dynamic decoded = json.decode(logStr);
      if (decoded is List) {
        final List<LibraryActivityEntry> loadedLogs = [];
        for (final dynamic item in decoded) {
          if (item is Map) {
            loadedLogs.add(LibraryActivityEntry(
              id: item['id']?.toString() ?? '',
              kind: LibraryActivityKind.values.firstWhere(
                (e) => _enumName(e) == item['kind'],
                orElse: () => LibraryActivityKind.playlistCreated,
              ),
              message: item['message']?.toString() ?? '',
              timestamp: DateTime.tryParse(item['timestamp']?.toString() ?? '') ?? DateTime.now(),
            ));
          }
        }

        // Filter out log entries older than 24 hours
        final DateTime cutoff = DateTime.now().subtract(const Duration(hours: 24));
        libraryActivityLogNotifier.value = loadedLogs.where((entry) => entry.timestamp.isAfter(cutoff)).toList();
      }
    } catch (_) {}
  }
  libraryActivityLogNotifier.addListener(() {
    final List<Map<String, dynamic>> list = libraryActivityLogNotifier.value.map((entry) => {
      'id': entry.id,
      'kind': _enumName(entry.kind),
      'message': entry.message,
      'timestamp': entry.timestamp.toIso8601String(),
    }).toList();
    _prefs.setString('library_activity_log', json.encode(list));
  });

  // 11. Favorite Album IDs
  final String? favAlbumsStr = _prefs.getString('favorite_album_ids');
  if (favAlbumsStr != null) {
    try {
      final dynamic decoded = json.decode(favAlbumsStr);
      if (decoded is List) {
        favoriteAlbumIdsNotifier.value = Set<String>.from(decoded.map((item) => item.toString()));
      }
    } catch (_) {}
  }
  favoriteAlbumIdsNotifier.addListener(() {
    _prefs.setString('favorite_album_ids', json.encode(favoriteAlbumIdsNotifier.value.toList()));
  });

  // 12. Favorite Song IDs
  final String? favSongsStr = _prefs.getString('favorite_song_ids');
  if (favSongsStr != null) {
    try {
      final dynamic decoded = json.decode(favSongsStr);
      if (decoded is List) {
        favoriteSongIdsNotifier.value = Set<String>.from(decoded.map((item) => item.toString()));
      }
    } catch (_) {}
  }
  favoriteSongIdsNotifier.addListener(() {
    _prefs.setString('favorite_song_ids', json.encode(favoriteSongIdsNotifier.value.toList()));
  });

  // 13. Playlists (including edits, creation, and deletion)
  final String? playlistsStr = _prefs.getString('playlists');
  if (playlistsStr != null) {
    try {
      final dynamic decoded = json.decode(playlistsStr);
      if (decoded is List) {
        final List<AppPlaylist> loadedPlaylists = [];
        for (final dynamic item in decoded) {
          if (item is Map) {
            loadedPlaylists.add(AppPlaylist(
              name: item['name']?.toString() ?? '',
              songs: item['songs'] as List<dynamic>? ?? <dynamic>[],
              createdAt: DateTime.tryParse(item['createdAt']?.toString() ?? '') ?? DateTime.now(),
              sortMode: PlaylistSortMode.values.firstWhere(
                (e) => _enumName(e) == item['sortMode'],
                orElse: () => PlaylistSortMode.manual,
              ),
            ));
          }
        }
        playlistsNotifier.value = loadedPlaylists;
      }
    } catch (_) {}
  }
  playlistsNotifier.addListener(() {
    final List<Map<String, dynamic>> list = playlistsNotifier.value.map((p) => {
      'name': p.name,
      'songs': p.songs,
      'createdAt': p.createdAt.toIso8601String(),
      'sortMode': _enumName(p.sortMode),
    }).toList();
    _prefs.setString('playlists', json.encode(list));
  });

  // 14. Recent Items (Listening History)
  final String? recentItemsStr = _prefs.getString('recent_items');
  if (recentItemsStr != null) {
    try {
      final dynamic decoded = json.decode(recentItemsStr);
      if (decoded is List) {
        final List<RecentLibraryItem> loadedItems = [];
        for (final dynamic item in decoded) {
          if (item is Map) {
            loadedItems.add(RecentLibraryItem(
              id: item['id']?.toString() ?? '',
              title: item['title']?.toString() ?? '',
              subtitle: item['subtitle']?.toString() ?? '',
              imageId: item['imageId']?.toString() ?? '',
              type: RecentLibraryItemType.values.firstWhere(
                (e) => _enumName(e) == item['type'],
                orElse: () => RecentLibraryItemType.song,
              ),
              source: item['source'] is Map ? Map<String, dynamic>.from(item['source'] as Map) : <String, dynamic>{},
              playlistSongs: item['playlistSongs'] as List<dynamic>? ?? <dynamic>[],
              playedAt: DateTime.tryParse(item['playedAt']?.toString() ?? '') ?? DateTime.now(),
            ));
          }
        }
        recentItemsNotifier.value = loadedItems;
      }
    } catch (_) {}
  }
  recentItemsNotifier.addListener(() {
    final List<Map<String, dynamic>> list = recentItemsNotifier.value.map((item) => {
      'id': item.id,
      'title': item.title,
      'subtitle': item.subtitle,
      'imageId': item.imageId,
      'type': _enumName(item.type),
      'source': item.source,
      'playlistSongs': item.playlistSongs,
      'playedAt': item.playedAt.toIso8601String(),
    }).toList();
    _prefs.setString('recent_items', json.encode(list));
  });

  // 15. Source Playback Presets (Album/Playlist shuffle & repeat presets)
  final String? presetsStr = _prefs.getString('source_playback_presets');
  if (presetsStr != null) {
    try {
      final dynamic decoded = json.decode(presetsStr);
      if (decoded is Map) {
        final Map<String, SourcePlaybackPreset> map = {};
        decoded.forEach((key, value) {
          if (value is Map) {
            final String repeatName = value['repeat']?.toString() ?? '';
            map[key as String] = SourcePlaybackPreset(
              shuffleEnabled: value['shuffle'] as bool? ?? false,
              repeatMode: LoopMode.values.firstWhere(
                (e) => _enumName(e) == repeatName,
                orElse: () => LoopMode.off,
              ),
            );
          }
        });
        sourcePlaybackPresetsNotifier.value = map;
      }
    } catch (_) {}
  }
  sourcePlaybackPresetsNotifier.addListener(() {
    final Map<String, dynamic> mapJson = {};
    for (final MapEntry<String, SourcePlaybackPreset> entry in sourcePlaybackPresetsNotifier.value.entries) {
      final SourcePlaybackPreset preset = entry.value;
      mapJson[entry.key] = {
        'shuffle': preset.shuffleEnabled,
        'repeat': _enumName(preset.repeatMode),
      };
    }
    _prefs.setString('source_playback_presets', json.encode(mapJson));
  });
}
