import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../screens/player_screen.dart';
import '../services/audio_service.dart';
import '../services/theme_state.dart';

class AppMiniPlayer extends StatelessWidget {
  const AppMiniPlayer({super.key, this.bottomMargin = 8});

  final double bottomMargin;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeChoice>(
      valueListenable: appThemeChoiceNotifier,
      builder: (context, _, child) {
        final AppThemePalette palette = activeAppPalette(context);

        return ValueListenableBuilder<String>(
          valueListenable: currentSongNotifier,
          builder: (context, song, child) {
            if (song == 'Nothing playing') {
              return const SizedBox.shrink();
            }

            return GestureDetector(
              onHorizontalDragEnd: (details) {
                final double velocity = details.primaryVelocity ?? 0;
                if (velocity < -250) {
                  playNext();
                } else if (velocity > 250) {
                  playPrev();
                }
              },
              child: Container(
                margin: EdgeInsets.fromLTRB(12, 0, 12, bottomMargin),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const PlayerScreen(
                                onNext: playNext,
                                onPrev: playPrev,
                              ),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            ValueListenableBuilder<String>(
                              valueListenable: currentImageNotifier,
                              builder: (context, image, child) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: image.isNotEmpty
                                      ? Image.network(
                                          image,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const _MiniArtFallback();
                                          },
                                        )
                                      : const _MiniArtFallback(),
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: currentArtistNotifier,
                                builder: (context, artist, child) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        song,
                                        style: TextStyle(
                                          color: palette.text,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        artist,
                                        style: TextStyle(
                                          color: palette.mutedText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: isPlayingNotifier,
                      builder: (context, isPlaying, child) {
                        return IconButton(
                          icon: Icon(
                            isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: palette.accent,
                          ),
                          onPressed: togglePlayPause,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniArtFallback extends StatelessWidget {
  const _MiniArtFallback();

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Container(
      width: 48,
      height: 48,
      color: palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        CupertinoIcons.music_note,
        color: palette.accent,
        size: 20,
      ),
    );
  }
}
