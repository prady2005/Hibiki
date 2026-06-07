import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/library_state.dart';
import '../services/theme_state.dart';

class PlaylistEditSheet extends StatefulWidget {
  const PlaylistEditSheet({
    super.key,
    required this.playlist,
    required this.onSave,
  });

  final AppPlaylist playlist;
  final ValueChanged<AppPlaylist> onSave;

  @override
  State<PlaylistEditSheet> createState() => _PlaylistEditSheetState();
}

class _PlaylistEditSheetState extends State<PlaylistEditSheet> {
  late PlaylistSortMode _sortMode;
  late List<dynamic> _workingSongs;

  @override
  void initState() {
    super.initState();
    _sortMode = widget.playlist.sortMode;
    _workingSongs = List<dynamic>.from(widget.playlist.songs);
  }

  void _selectSortMode(PlaylistSortMode mode) {
    setState(() {
      _sortMode = mode;
      if (mode == PlaylistSortMode.manual) {
        return;
      }
      _workingSongs = sortPlaylistSongs(_workingSongs, mode);
    });
  }

  void _save() {
    final updated = AppPlaylist(
      name: widget.playlist.name,
      songs: _workingSongs.map(stampPlaylistSong).toList(),
      createdAt: widget.playlist.createdAt,
      sortMode: _sortMode,
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit playlist',
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
            const SizedBox(height: 6),
            Text(
              widget.playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Sort songs',
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...PlaylistSortMode.values.map((mode) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SortModeTile(
                  mode: mode,
                  isSelected: _sortMode == mode,
                  onTap: () => _selectSortMode(mode),
                ),
              );
            }),
            if (_sortMode == PlaylistSortMode.manual) ...[
              const SizedBox(height: 14),
              Text(
                'Drag to reorder',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _sortMode == PlaylistSortMode.manual
                  ? ReorderableListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _workingSongs.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }
                          final dynamic song = _workingSongs.removeAt(oldIndex);
                          _workingSongs.insert(newIndex, song);
                        });
                      },
                      itemBuilder: (context, index) {
                        final dynamic song = _workingSongs[index];
                        return _ReorderSongTile(
                          key: ValueKey<String>(itemId(song).isEmpty ? '$index' : itemId(song)),
                          title: _songTitle(song),
                          artist: _songArtist(song),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _workingSongs.length,
                      itemBuilder: (context, index) {
                        final dynamic song = _workingSongs[index];
                        return _PreviewSongTile(
                          title: _songTitle(song),
                          artist: _songArtist(song),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.background,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _save,
                child: const Text(
                  'Save changes',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortModeTile extends StatelessWidget {
  const _SortModeTile({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  final PlaylistSortMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Material(
      color: isSelected ? palette.accent.withOpacity(0.14) : palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? palette.accent.withOpacity(0.45) : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: isSelected ? palette.accent : palette.mutedText,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.description,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderSongTile extends StatelessWidget {
  const _ReorderSongTile({
    super.key,
    required this.title,
    required this.artist,
  });

  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.bars, color: palette.mutedText, size: 18),
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
                const SizedBox(height: 2),
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
        ],
      ),
    );
  }
}

class _PreviewSongTile extends StatelessWidget {
  const _PreviewSongTile({
    required this.title,
    required this.artist,
  });

  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
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
                const SizedBox(height: 2),
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
        ],
      ),
    );
  }
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
