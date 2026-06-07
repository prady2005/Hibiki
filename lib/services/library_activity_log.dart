import 'package:flutter/foundation.dart';

enum LibraryActivityKind {
  playlistCreated,
  playlistDeleted,
  playlistSongAdded,
  playlistSongRemoved,
  playlistReordered,
  albumSongAdded,
  albumSongRemoved,
  albumCreated,
  albumDeleted,
}

class LibraryActivityEntry {
  const LibraryActivityEntry({
    required this.id,
    required this.kind,
    required this.message,
    required this.timestamp,
  });

  final String id;
  final LibraryActivityKind kind;
  final String message;
  final DateTime timestamp;
}

final libraryActivityLogNotifier = ValueNotifier<List<LibraryActivityEntry>>(
  <LibraryActivityEntry>[],
);

void recordLibraryActivity({
  required LibraryActivityKind kind,
  required String message,
}) {
  final entry = LibraryActivityEntry(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    kind: kind,
    message: message,
    timestamp: DateTime.now(),
  );

  libraryActivityLogNotifier.value = <LibraryActivityEntry>[
    entry,
    ...libraryActivityLogNotifier.value,
  ].take(100).toList();
}

String _quote(String value) => '"$value"';

void logPlaylistCreated(String playlistName) {
  recordLibraryActivity(
    kind: LibraryActivityKind.playlistCreated,
    message: 'Created playlist ${_quote(playlistName)}',
  );
}

void logPlaylistDeleted(String playlistName) {
  recordLibraryActivity(
    kind: LibraryActivityKind.playlistDeleted,
    message: 'Deleted playlist ${_quote(playlistName)}',
  );
}

void logPlaylistSongAdded(String playlistName, String songTitle) {
  recordLibraryActivity(
    kind: LibraryActivityKind.playlistSongAdded,
    message: 'Added ${_quote(songTitle)} to playlist ${_quote(playlistName)}',
  );
}

void logPlaylistSongsRemoved(String playlistName, int count) {
  recordLibraryActivity(
    kind: LibraryActivityKind.playlistSongRemoved,
    message: count == 1
        ? 'Removed 1 song from playlist ${_quote(playlistName)}'
        : 'Removed $count songs from playlist ${_quote(playlistName)}',
  );
}

void logPlaylistReordered(String playlistName) {
  recordLibraryActivity(
    kind: LibraryActivityKind.playlistReordered,
    message: 'Rearranged song order in playlist ${_quote(playlistName)}',
  );
}

void logAlbumSongAdded(String albumName, String songTitle) {
  recordLibraryActivity(
    kind: LibraryActivityKind.albumSongAdded,
    message: 'Added ${_quote(songTitle)} to album ${_quote(albumName)}',
  );
}

void logAlbumSongRemoved(String albumName, String songTitle) {
  recordLibraryActivity(
    kind: LibraryActivityKind.albumSongRemoved,
    message: 'Removed ${_quote(songTitle)} from album ${_quote(albumName)}',
  );
}

void logAlbumCreated(String albumName) {
  recordLibraryActivity(
    kind: LibraryActivityKind.albumCreated,
    message: 'Created album ${_quote(albumName)}',
  );
}

void logAlbumDeleted(String albumName) {
  recordLibraryActivity(
    kind: LibraryActivityKind.albumDeleted,
    message: 'Deleted album ${_quote(albumName)}',
  );
}
