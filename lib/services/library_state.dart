import 'package:flutter/foundation.dart';

import 'library_activity_log.dart';

final favoriteAlbumIdsNotifier = ValueNotifier<Set<String>>(<String>{});
final favoriteSongIdsNotifier = ValueNotifier<Set<String>>(<String>{});
final playlistsNotifier = ValueNotifier<List<AppPlaylist>>(<AppPlaylist>[]);
final recentItemsNotifier = ValueNotifier<List<RecentLibraryItem>>(
  <RecentLibraryItem>[],
);

enum PlaylistSortMode {
  manual,
  alphabeticalAz,
  recentlyAdded,
}

extension PlaylistSortModeLabel on PlaylistSortMode {
  String get label {
    switch (this) {
      case PlaylistSortMode.manual:
        return 'Manual order';
      case PlaylistSortMode.alphabeticalAz:
        return 'Alphabetical (A–Z)';
      case PlaylistSortMode.recentlyAdded:
        return 'Recently added';
    }
  }

  String get description {
    switch (this) {
      case PlaylistSortMode.manual:
        return 'Drag songs to arrange them yourself';
      case PlaylistSortMode.alphabeticalAz:
        return 'Sort by song title from A to Z';
      case PlaylistSortMode.recentlyAdded:
        return 'Newest additions appear first';
    }
  }
}

class AppPlaylist {
  const AppPlaylist({
    required this.name,
    required this.songs,
    required this.createdAt,
    this.sortMode = PlaylistSortMode.manual,
  });

  final String name;
  final List<dynamic> songs;
  final DateTime createdAt;
  final PlaylistSortMode sortMode;

  int get songCount => songs.length;

  String get id => '$name-${createdAt.microsecondsSinceEpoch}';
}

enum RecentLibraryItemType { song, album, playlist }

class RecentLibraryItem {
  const RecentLibraryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageId,
    required this.type,
    required this.source,
    required this.playedAt,
    this.playlistSongs = const <dynamic>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageId;
  final RecentLibraryItemType type;
  final Map<dynamic, dynamic> source;
  final DateTime playedAt;
  final List<dynamic> playlistSongs;

  bool get isAlbum => type == RecentLibraryItemType.album;
  bool get isPlaylist => type == RecentLibraryItemType.playlist;
}

String itemId(dynamic item) {
  final id = item is Map ? item['Id'] : null;
  return id?.toString() ?? '';
}

bool isAlbumFavorite(dynamic album) {
  final String id = itemId(album);
  if (id.isNotEmpty && favoriteAlbumIdsNotifier.value.contains(id)) {
    return true;
  }

  final userData = album is Map ? album['UserData'] : null;
  return userData is Map && userData['IsFavorite'] == true;
}

void toggleFavoriteAlbum(dynamic album) {
  final String id = itemId(album);
  if (id.isEmpty) return;

  final next = Set<String>.from(favoriteAlbumIdsNotifier.value);
  if (isAlbumFavorite(album)) {
    next.remove(id);
  } else {
    next.add(id);
  }
  favoriteAlbumIdsNotifier.value = next;
}

bool isSongFavorite(dynamic song) {
  final String id = itemId(song);
  return id.isNotEmpty && favoriteSongIdsNotifier.value.contains(id);
}

void toggleFavoriteSong(dynamic song) {
  final String id = itemId(song);
  if (id.isEmpty) return;

  final next = Set<String>.from(favoriteSongIdsNotifier.value);
  if (isSongFavorite(song)) {
    next.remove(id);
  } else {
    next.add(id);
  }
  favoriteSongIdsNotifier.value = next;
}

DateTime? playlistSongAddedAt(dynamic song) {
  if (song is! Map) return null;
  final dynamic addedAt = song['_PlaylistAddedAt'];
  if (addedAt is int) {
    return DateTime.fromMillisecondsSinceEpoch(addedAt);
  }
  if (addedAt is DateTime) {
    return addedAt;
  }
  return null;
}

dynamic stampPlaylistSong(dynamic song) {
  if (song is! Map) return song;
  final copy = Map<dynamic, dynamic>.from(song);
  copy['_PlaylistAddedAt'] ??= DateTime.now().millisecondsSinceEpoch;
  return copy;
}

List<dynamic> sortPlaylistSongs(List<dynamic> songs, PlaylistSortMode mode) {
  final ordered = List<dynamic>.from(songs);
  switch (mode) {
    case PlaylistSortMode.manual:
      return ordered;
    case PlaylistSortMode.alphabeticalAz:
      ordered.sort((a, b) => sortTitle(a).compareTo(sortTitle(b)));
      return ordered;
    case PlaylistSortMode.recentlyAdded:
      ordered.sort((a, b) {
        final int aMillis = playlistSongAddedAt(a)?.millisecondsSinceEpoch ?? 0;
        final int bMillis = playlistSongAddedAt(b)?.millisecondsSinceEpoch ?? 0;
        return bMillis.compareTo(aMillis);
      });
      return ordered;
  }
}

AppPlaylist? findPlaylistById(String playlistId) {
  for (final AppPlaylist playlist in playlistsNotifier.value) {
    if (playlist.id == playlistId) {
      return playlist;
    }
  }
  return null;
}

void replacePlaylist(AppPlaylist playlist) {
  playlistsNotifier.value = playlistsNotifier.value.map((item) {
    return item.id == playlist.id ? playlist : item;
  }).toList();
}

void updatePlaylistContents({
  required String playlistId,
  required List<dynamic> songs,
  PlaylistSortMode? sortMode,
}) {
  playlistsNotifier.value = playlistsNotifier.value.map((item) {
    if (item.id != playlistId) return item;
    return AppPlaylist(
      name: item.name,
      songs: songs.map(stampPlaylistSong).toList(),
      createdAt: item.createdAt,
      sortMode: sortMode ?? item.sortMode,
    );
  }).toList();
}

void applyPlaylistSortMode(String playlistId, PlaylistSortMode mode) {
  final AppPlaylist? playlist = findPlaylistById(playlistId);
  if (playlist == null) return;

  final List<dynamic> ordered = mode == PlaylistSortMode.manual
      ? List<dynamic>.from(playlist.songs)
      : sortPlaylistSongs(playlist.songs, mode);

  updatePlaylistContents(
    playlistId: playlistId,
    songs: ordered,
    sortMode: mode,
  );
}

bool removeSongsFromPlaylist(String playlistId, Set<String> songIds) {
  if (songIds.isEmpty) return false;

  final AppPlaylist? playlist = findPlaylistById(playlistId);
  if (playlist == null) return false;

  var removedAny = false;
  var removedCount = 0;
  playlistsNotifier.value = playlistsNotifier.value.map((item) {
    if (item.id != playlistId) return item;

    final List<dynamic> remainingSongs = item.songs.where((song) {
      return !songIds.contains(itemId(song));
    }).toList();

    if (remainingSongs.length == item.songs.length) {
      return item;
    }

    removedAny = true;
    removedCount = item.songs.length - remainingSongs.length;
    return AppPlaylist(
      name: item.name,
      songs: remainingSongs,
      createdAt: item.createdAt,
      sortMode: item.sortMode,
    );
  }).toList();

  if (removedAny) {
    logPlaylistSongsRemoved(playlist.name, removedCount);
  }

  return removedAny;
}

void addPlaylist(String name, List<dynamic> songs) {
  final String cleanName = name.trim();
  if (cleanName.isEmpty || songs.isEmpty) return;

  playlistsNotifier.value = <AppPlaylist>[
    AppPlaylist(
      name: cleanName,
      songs: songs.map(stampPlaylistSong).toList(),
      createdAt: DateTime.now(),
    ),
    ...playlistsNotifier.value,
  ];
  logPlaylistCreated(cleanName);
}

String nextUntitledPlaylistName() {
  var index = 1;
  final Set<String> existingNames =
      playlistsNotifier.value.map((playlist) => playlist.name).toSet();
  while (existingNames.contains('Untitled Playlist $index')) {
    index++;
  }
  return 'Untitled Playlist $index';
}

void deletePlaylist(AppPlaylist playlist) {
  playlistsNotifier.value = playlistsNotifier.value.where((item) {
    return item.id != playlist.id;
  }).toList();
  recentItemsNotifier.value = recentItemsNotifier.value.where((item) {
    return item.type != RecentLibraryItemType.playlist || item.id != playlist.id;
  }).toList();
  logPlaylistDeleted(playlist.name);
}

bool addSongToPlaylist(AppPlaylist playlist, dynamic song) {
  final String songId = itemId(song);
  if (songId.isEmpty) return false;
  if (playlist.songs.any((item) => itemId(item) == songId)) return false;

  playlistsNotifier.value = playlistsNotifier.value.map((item) {
    if (item.id != playlist.id) return item;
    return AppPlaylist(
      name: item.name,
      songs: <dynamic>[...item.songs, stampPlaylistSong(song)],
      createdAt: item.createdAt,
      sortMode: item.sortMode,
    );
  }).toList();

  final String songTitle = song is Map ? (song['Name']?.toString() ?? 'Unknown track') : 'Unknown track';
  logPlaylistSongAdded(playlist.name, songTitle);

  return true;
}

void recordRecentPlayback(dynamic item) {
  if (item is! Map) return;

  final RecentLibraryItem? recentItem = _recentItemFromPlayback(item);
  if (recentItem == null) return;

  final List<RecentLibraryItem> next = <RecentLibraryItem>[
    recentItem,
    ...recentItemsNotifier.value.where((item) {
      return item.type != recentItem.type || item.id != recentItem.id;
    }),
  ].take(15).toList();

  recentItemsNotifier.value = next;
}

void recordRecentPlaylist(AppPlaylist playlist) {
  if (playlist.songs.isEmpty) return;

  final recentItem = RecentLibraryItem(
    id: playlist.id,
    title: playlist.name,
    subtitle: '${playlist.songCount} songs',
    imageId: '',
    type: RecentLibraryItemType.playlist,
    source: <dynamic, dynamic>{},
    playlistSongs: List<dynamic>.from(playlist.songs),
    playedAt: DateTime.now(),
  );

  final List<RecentLibraryItem> next = <RecentLibraryItem>[
    recentItem,
    ...recentItemsNotifier.value.where((item) {
      return item.type != recentItem.type || item.id != recentItem.id;
    }),
  ].take(15).toList();

  recentItemsNotifier.value = next;
}

RecentLibraryItem? _recentItemFromPlayback(Map<dynamic, dynamic> item) {
  final String albumId = _stringValue(item['AlbumId']);
  final String albumTitle = _stringValue(item['Album']);
  final String parentId = _stringValue(item['ParentId']);
  final playedFromAlbum = item['_PlayedFromAlbum'] == true;

  if (playedFromAlbum) {
    final id = albumId.isNotEmpty ? albumId : parentId;
    if (id.isEmpty) return null;

    final title = albumTitle.isNotEmpty ? albumTitle : 'Unknown album';
    return RecentLibraryItem(
      id: id,
      title: title,
      subtitle: _artistName(item),
      imageId: id,
      type: RecentLibraryItemType.album,
      source: <dynamic, dynamic>{
        'Id': id,
        'Name': title,
        'AlbumArtist': _artistName(item),
      },
      playedAt: DateTime.now(),
    );
  }

  final String songId = itemId(item);
  if (songId.isEmpty) return null;

  return RecentLibraryItem(
    id: songId,
    title: _stringValue(item['Name'], fallback: 'Unknown track'),
    subtitle: _artistName(item),
    imageId: songId,
    type: RecentLibraryItemType.song,
    source: Map<dynamic, dynamic>.from(item),
    playedAt: DateTime.now(),
  );
}

bool isStandaloneSong(dynamic song) {
  if (song is! Map) return false;
  return _stringValue(song['AlbumId']).isEmpty && _stringValue(song['Album']).isEmpty;
}

bool belongsToAnyAlbum(dynamic song, Set<String> albumIds) {
  if (song is! Map) return false;
  final String albumId = _stringValue(song['AlbumId']);
  final String parentId = _stringValue(song['ParentId']);
  return albumIds.contains(albumId) || albumIds.contains(parentId);
}

String sortTitle(dynamic item) {
  if (item is! Map) return '';
  final String sortName = _stringValue(item['SortName']);
  if (sortName.isNotEmpty) return sortName.toLowerCase();
  return _stringValue(item['Name']).toLowerCase();
}

String _artistName(Map<dynamic, dynamic> item) {
  final artists = item['Artists'];
  if (artists is List && artists.isNotEmpty && artists.first != null) {
    return artists.first.toString();
  }

  final albumArtist = item['AlbumArtist'];
  if (albumArtist != null && albumArtist.toString().isNotEmpty) {
    return albumArtist.toString();
  }

  return 'Unknown';
}

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}
