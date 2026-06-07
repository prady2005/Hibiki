import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../services/sleep_timer_settings.dart';
import '../services/theme_state.dart';
import 'app_feedback.dart';

class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({super.key});

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet> {
  double customMinutes = 20;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sleep timer',
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
            const SizedBox(height: 8),
            ValueListenableBuilder<DateTime?>(
              valueListenable: sleepTimerEndsAtNotifier,
              builder: (context, endsAt, child) {
                final Duration? remaining = endsAt?.difference(DateTime.now());
                final bool isActive = remaining != null && !remaining.isNegative;
                return Text(
                  isActive
                      ? 'Music will stop in ${remaining.inMinutes + 1} min'
                      : 'Choose when the music should stop.',
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<int>(
              valueListenable: sleepTimerPresetCountNotifier,
              builder: (context, _, child) {
                return ValueListenableBuilder<List<int>>(
                  valueListenable: sleepTimerPresetMinutesNotifier,
                  builder: (context, presetMinutes, child) {
                    final List<int> presets = sleepTimerPresetMinutesForPlayer();
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final int minutes in presets)
                          _SleepTimerButton(
                            label: formatSleepTimerPresetLabel(minutes),
                            onTap: () {
                              setSleepTimer(Duration(minutes: minutes));
                              showAppFeedback(
                                context,
                                'Sleep timer set for $minutes minutes',
                              );
                              Navigator.pop(context);
                            },
                          ),
                      ],
                    );
                  },
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: sleepTimerCustomEnabledNotifier,
              builder: (context, customEnabled, child) {
                if (!customEnabled) {
                  return const SizedBox(height: 8);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    Text(
                      'Custom: ${customMinutes.round()} min',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Slider(
                      min: 1,
                      max: 120,
                      divisions: 119,
                      value: customMinutes,
                      activeColor: palette.accent,
                      inactiveColor: palette.border,
                      onChanged: (value) {
                        setState(() {
                          customMinutes = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: palette.accent,
                              foregroundColor: readableTextOn(palette.accent),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () {
                              setSleepTimer(Duration(minutes: customMinutes.round()));
                              showAppFeedback(
                                context,
                                'Sleep timer set for ${customMinutes.round()} minutes',
                              );
                              Navigator.pop(context);
                            },
                            child: const Text('Set custom timer'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<DateTime?>(
                          valueListenable: sleepTimerEndsAtNotifier,
                          builder: (context, endsAt, child) {
                            return _SleepTimerButton(
                              label: 'Cancel',
                              isEnabled: endsAt != null,
                              onTap: () {
                                cancelSleepTimer();
                                showAppFeedback(context, 'Sleep timer cancelled');
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: sleepTimerCustomEnabledNotifier,
              builder: (context, customEnabled, child) {
                if (customEnabled) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ValueListenableBuilder<DateTime?>(
                    valueListenable: sleepTimerEndsAtNotifier,
                    builder: (context, endsAt, child) {
                      return Align(
                        alignment: Alignment.centerRight,
                        child: _SleepTimerButton(
                          label: 'Cancel',
                          isEnabled: endsAt != null,
                          onTap: () {
                            cancelSleepTimer();
                            showAppFeedback(context, 'Sleep timer cancelled');
                            Navigator.pop(context);
                          },
                        ),
                      );
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

class _SleepTimerButton extends StatelessWidget {
  const _SleepTimerButton({
    required this.label,
    required this.onTap,
    this.isEnabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: palette.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
