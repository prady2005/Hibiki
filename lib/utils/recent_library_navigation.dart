import 'package:flutter/material.dart';

import '../screens/album_screen.dart';
import '../screens/player_screen.dart';
import '../screens/playlist_screen.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/library_state.dart';

Future<void> openRecentLibraryItem(
  BuildContext context,
  RecentLibraryItem item, {
  required List<dynamic> songs,
}) async {
  if (item.isAlbum) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AlbumScreen(album: item.source),
      ),
    );
    return;
  }

  if (item.isPlaylist) {
    if (item.playlistSongs.isEmpty) return;

    final AppPlaylist? playlist = findPlaylistById(item.id);

    if (playlist != null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(playlist: playlist),
        ),
      );
      return;
    }

    final dynamic firstSong = item.playlistSongs.first;
    final String id = itemId(firstSong);
    if (id.isEmpty) return;

    final NavigatorState navigator = Navigator.of(context);
    await playSong(
      getAudioUrl(id),
      title: _songTitle(firstSong),
      image: getImageUrl(id),
      artist: _songArtist(firstSong),
      index: 0,
      queue: item.playlistSongs,
      trackDuration: durationFromTicks(firstSong['RunTimeTicks']),
      playbackSourceType: 'Playlist',
      playbackSourceName: item.title,
    );
    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const PlayerScreen(
          onNext: playNext,
          onPrev: playPrev,
        ),
      ),
    );
    return;
  }

  final int songIndex = songs.indexWhere((song) => itemId(song) == item.id);
  if (songIndex == -1) return;

  final NavigatorState navigator = Navigator.of(context);
  await playSong(
    getAudioUrl(item.id),
    title: item.title,
    image: getImageUrl(item.imageId),
    artist: item.subtitle,
    index: songIndex,
    queue: songs,
    trackDuration: durationFromTicks(songs[songIndex]['RunTimeTicks']),
  );
  if (!context.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => const PlayerScreen(
        onNext: playNext,
        onPrev: playPrev,
      ),
    ),
  );
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
