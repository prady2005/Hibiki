import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/library_state.dart';
import '../services/theme_state.dart';
import '../utils/recent_library_navigation.dart';
import '../widgets/recent_library_item_tile.dart';

enum _HistoryFilter { songs, albums, playlists }

class ListeningHistoryScreen extends StatefulWidget {
  const ListeningHistoryScreen({super.key});

  @override
  State<ListeningHistoryScreen> createState() => _ListeningHistoryScreenState();
}

class _ListeningHistoryScreenState extends State<ListeningHistoryScreen> {
  _HistoryFilter _filter = _HistoryFilter.songs;
  List<dynamic> _songs = <dynamic>[];
  bool _isLoadingSongs = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      final List<dynamic> data = await fetchSongs();
      if (!mounted) return;
      setState(() {
        _songs = data;
        _isLoadingSongs = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSongs = false);
    }
  }

  List<RecentLibraryItem> _filteredItems(List<RecentLibraryItem> items) {
    switch (_filter) {
      case _HistoryFilter.songs:
        return items.where((item) => !item.isAlbum && !item.isPlaylist).toList();
      case _HistoryFilter.albums:
        return items.where((item) => item.isAlbum).toList();
      case _HistoryFilter.playlists:
        return items.where((item) => item.isPlaylist).toList();
    }
  }

  String get _emptyMessage {
    switch (_filter) {
      case _HistoryFilter.songs:
        return 'No recently played songs yet';
      case _HistoryFilter.albums:
        return 'No recently played albums yet';
      case _HistoryFilter.playlists:
        return 'No recently played playlists yet';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(CupertinoIcons.chevron_back, color: palette.accent),
                  ),
                  Expanded(
                    child: Text(
                      'Listening history',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    for (final entry in <(_HistoryFilter, String)>[
                      (_HistoryFilter.songs, 'Songs'),
                      (_HistoryFilter.albums, 'Albums'),
                      (_HistoryFilter.playlists, 'Playlists'),
                    ])
                      Expanded(
                        child: _HistoryFilterButton(
                          label: entry.$2,
                          selected: _filter == entry.$1,
                          onTap: () => setState(() => _filter = entry.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ValueListenableBuilder<List<RecentLibraryItem>>(
                valueListenable: recentItemsNotifier,
                builder: (context, items, child) {
                  final List<RecentLibraryItem> filtered = _filteredItems(items);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _emptyMessage,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final RecentLibraryItem item = filtered[index];
                      return RecentLibraryItemTile(
                        item: item,
                        onTap: _isLoadingSongs
                            ? () {}
                            : () => openRecentLibraryItem(
                                  context,
                                  item,
                                  songs: _songs,
                                ),
                      );
                    },
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

class _HistoryFilterButton extends StatelessWidget {
  const _HistoryFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? readableTextOn(palette.accent) : palette.mutedText,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
