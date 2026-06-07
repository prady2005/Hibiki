import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/library_activity_log.dart';
import '../services/theme_state.dart';

class RecentlyChangedScreen extends StatelessWidget {
  const RecentlyChangedScreen({super.key});

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
                      'Recently changed',
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Read-only log of playlist and library changes in this app.',
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ValueListenableBuilder<List<LibraryActivityEntry>>(
                valueListenable: libraryActivityLogNotifier,
                builder: (context, entries, child) {
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        'No changes logged yet',
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
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final LibraryActivityEntry entry = entries[index];
                      return _ActivityLogTile(entry: entry);
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

class _ActivityLogTile extends StatelessWidget {
  const _ActivityLogTile({required this.entry});

  final LibraryActivityEntry entry;

  IconData get _icon {
    switch (entry.kind) {
      case LibraryActivityKind.playlistCreated:
      case LibraryActivityKind.albumCreated:
        return CupertinoIcons.plus_circle_fill;
      case LibraryActivityKind.playlistDeleted:
      case LibraryActivityKind.albumDeleted:
        return CupertinoIcons.minus_circle_fill;
      case LibraryActivityKind.playlistSongAdded:
      case LibraryActivityKind.albumSongAdded:
        return CupertinoIcons.arrow_down_circle_fill;
      case LibraryActivityKind.playlistSongRemoved:
      case LibraryActivityKind.albumSongRemoved:
        return CupertinoIcons.arrow_up_circle_fill;
      case LibraryActivityKind.playlistReordered:
        return CupertinoIcons.arrow_up_arrow_down_circle_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final String timeLabel = DateFormat('MMM d · h:mm a').format(entry.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: palette.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timeLabel,
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
