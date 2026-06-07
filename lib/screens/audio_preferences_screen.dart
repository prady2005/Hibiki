import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/audio_preferences_settings.dart';
import '../services/audio_service.dart';
import '../services/equalizer_settings.dart';
import '../services/theme_state.dart';
import 'equalizer_screen.dart';

class AudioPreferencesScreen extends StatelessWidget {
  const AudioPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(CupertinoIcons.back, color: palette.text),
                ),
                Expanded(
                  child: Text(
                    'Audio preferences',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ValueListenableBuilder<EqualizerPreset>(
              valueListenable: equalizerPresetNotifier,
              builder: (context, preset, _) {
                return _AudioPreferenceNavSection(
                  palette: palette,
                  icon: CupertinoIcons.music_note_2,
                  title: 'Equalizer',
                  subtitle: equalizerPresetLabel(preset),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const EqualizerScreen(),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<bool>(
              valueListenable: volumeNormalizationEnabledNotifier,
              builder: (context, enabled, _) {
                return _AudioPreferenceSection(
                  palette: palette,
                  icon: CupertinoIcons.speaker_2_fill,
                  title: 'Volume normalization',
                  subtitle:
                      'Balance loud and quiet tracks so playback feels more even.',
                  trailing: CupertinoSwitch(
                    value: enabled,
                    activeTrackColor: palette.accent,
                    onChanged: (value) async {
                      volumeNormalizationEnabledNotifier.value = value;
                      await applyVolumeNormalization();
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: crossfadeSecondsNotifier,
              builder: (context, seconds, _) {
                return _AudioPreferenceSection(
                  palette: palette,
                  icon: Icons.compare_arrows,
                  title: 'Crossfade',
                  subtitle:
                      'Let the next song gently overlap the end of the current song.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              max: 10,
                              divisions: 10,
                              value: seconds,
                              activeColor: palette.accent,
                              inactiveColor: palette.border,
                              label: '${seconds.round()}s',
                              onChanged: (value) {
                                crossfadeSecondsNotifier.value = value;
                              },
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${seconds.round()}s',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<bool>(
              valueListenable: gaplessPlaybackEnabledNotifier,
              builder: (context, enabled, _) {
                return _AudioPreferenceSection(
                  palette: palette,
                  icon: CupertinoIcons.forward_fill,
                  title: 'Gapless playback',
                  subtitle:
                      'Remove silence between tracks, useful for live albums and mixes.',
                  trailing: CupertinoSwitch(
                    value: enabled,
                    activeTrackColor: palette.accent,
                    onChanged: (value) {
                      gaplessPlaybackEnabledNotifier.value = value;
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPreferenceNavSection extends StatelessWidget {
  const _AudioPreferenceNavSection({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: palette.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: palette.mutedText.withOpacity(0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_forward, color: palette.mutedText, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AudioPreferenceSection extends StatelessWidget {
  const _AudioPreferenceSection({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
    this.trailing,
  });

  final AppThemePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: palette.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.mutedText.withOpacity(0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 14),
            child!,
          ],
        ],
      ),
    );
  }
}
