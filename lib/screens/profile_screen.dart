import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/theme_state.dart';
import '../widgets/app_feedback.dart';
import '../widgets/sleep_timer_presets_sheet.dart';
import 'audio_preferences_screen.dart';
import 'help_feedback_screen.dart';
import 'listening_history_screen.dart';
import 'recently_changed_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 168),
          children: [
            Text(
              'Settings',
              style: TextStyle(
                color: palette.text,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.9,
                height: 1,
              ),
            ),
            const SizedBox(height: 24),
            _ProfileSectionTitle(title: 'Listening', palette: palette),
            const SizedBox(height: 10),
            _ProfileOption(
              icon: CupertinoIcons.time_solid,
              title: 'Listening history',
              subtitle: 'Recently played songs, albums, and playlists',
              palette: palette,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ListeningHistoryScreen(),
                  ),
                );
              },
            ),
            _ProfileOption(
              icon: CupertinoIcons.moon_zzz_fill,
              title: 'Sleep timer presets',
              subtitle: 'Preset count, durations, and custom timer',
              palette: palette,
              onTap: _showSleepTimerPresetsSheet,
            ),
            _ProfileOption(
              icon: CupertinoIcons.arrow_clockwise_circle_fill,
              title: 'Recently changed',
              subtitle: 'Log of playlist and library edits',
              palette: palette,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const RecentlyChangedScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            _ProfileSectionTitle(title: 'App', palette: palette),
            const SizedBox(height: 10),
            _ProfileOption(
              icon: CupertinoIcons.slider_horizontal_3,
              title: 'Audio preferences',
              subtitle: 'Ideas for quality and playback controls',
              palette: palette,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AudioPreferencesScreen(),
                  ),
                );
              },
            ),
            ValueListenableBuilder<AppThemeChoice>(
              valueListenable: appThemeChoiceNotifier,
              builder: (context, themeChoice, _) {
                return _ProfileOption(
                  icon: CupertinoIcons.paintbrush_fill,
                  title: 'Theme',
                  subtitle: appThemeChoiceLabel(themeChoice),
                  palette: activeAppPalette(context),
                  onTap: _showThemeSheet,
                );
              },
            ),
            _ProfileOption(
              icon: CupertinoIcons.question_circle_fill,
              title: 'Help and feedback',
              subtitle: 'Report problems or suggest improvements',
              palette: palette,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const HelpFeedbackScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerPresetsSheet() {
    final AppThemePalette palette = activeAppPalette(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const SleepTimerPresetsSheet(),
    );
  }

  void _showThemeSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ValueListenableBuilder<AppThemeChoice>(
          valueListenable: appThemeChoiceNotifier,
          builder: (context, selectedTheme, _) {
            final AppThemePalette palette = activeAppPalette(context);

            return Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final AppThemeChoice theme in AppThemeChoice.values)
                    _ThemeChoiceTile(
                      theme: theme,
                      selected: selectedTheme == theme,
                      palette: palette,
                      onTap: () {
                        appThemeChoiceNotifier.value = theme;
                        showAppFeedback(
                          context,
                          '${appThemeChoiceLabel(theme)} theme applied',
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle({required this.title, required this.palette});

  final String title;
  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: palette.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final AppThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
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
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
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

class _ThemeChoiceTile extends StatelessWidget {
  const _ThemeChoiceTile({
    required this.theme,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final AppThemeChoice theme;
  final bool selected;
  final AppThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette previewPalette = paletteForChoice(
      theme,
      theme == AppThemeChoice.dark ? Brightness.dark : Brightness.light,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? palette.surfaceAlt : palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
          ),
        ),
        child: Row(
          children: [
            Row(
              children: [
                _ThemeSwatch(color: previewPalette.background),
                _ThemeSwatch(color: previewPalette.surfaceAlt),
                _ThemeSwatch(color: previewPalette.accent),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                appThemeChoiceLabel(theme),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selected) Icon(CupertinoIcons.check_mark_circled_solid, color: palette.accent),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 28,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withOpacity(0.1)),
      ),
    );
  }
}
