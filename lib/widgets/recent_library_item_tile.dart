import 'package:flutter/cupertino.dart';

import '../services/api_service.dart';
import '../services/library_state.dart';
import '../services/theme_state.dart';

class RecentLibraryItemTile extends StatelessWidget {
  const RecentLibraryItemTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  final RecentLibraryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final bool isAlbum = item.isAlbum;
    final bool isPlaylist = item.isPlaylist;
    final IconData fallbackIcon = isAlbum
        ? CupertinoIcons.square_stack_fill
        : isPlaylist
            ? CupertinoIcons.music_albums_fill
            : CupertinoIcons.music_note;
    final itemType = isAlbum
        ? 'Album'
        : isPlaylist
            ? 'Playlist'
            : 'Song';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isAlbum ? palette.surfaceAlt : palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.imageId.isEmpty
                  ? _RecentArtFallback(icon: fallbackIcon)
                  : Image.network(
                      getImageUrl(item.imageId),
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _RecentArtFallback(icon: fallbackIcon);
                      },
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
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
                    '$itemType · ${item.subtitle}',
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
            Icon(
              CupertinoIcons.chevron_forward,
              color: palette.accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentArtFallback extends StatelessWidget {
  const _RecentArtFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      width: 54,
      height: 54,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(icon, color: palette.accent, size: 22),
    );
  }
}
