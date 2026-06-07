import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/sleep_timer_settings.dart';
import '../services/theme_state.dart';
import 'app_feedback.dart';

class SleepTimerPresetsSheet extends StatefulWidget {
  const SleepTimerPresetsSheet({super.key});

  @override
  State<SleepTimerPresetsSheet> createState() => _SleepTimerPresetsSheetState();
}

class _SleepTimerPresetsSheetState extends State<SleepTimerPresetsSheet> {
  late int _presetCount;
  late List<int> _presetMinutes;
  late bool _customEnabled;

  @override
  void initState() {
    super.initState();
    _presetCount = sleepTimerPresetCountNotifier.value;
    _presetMinutes = sleepTimerPresetMinutesSnapshot();
    _customEnabled = sleepTimerCustomEnabledNotifier.value;
  }

  void _applyPresetCount(int count) {
    setState(() {
      _presetCount = count;
      while (_presetMinutes.length < count) {
        _presetMinutes.add(
          defaultSleepTimerPresetMinutes[
              _presetMinutes.length % defaultSleepTimerPresetMinutes.length],
        );
      }
      if (_presetMinutes.length > count) {
        _presetMinutes = _presetMinutes.take(count).toList();
      }
    });
  }

  void _save() {
    setSleepTimerPresetCount(_presetCount);
    updateSleepTimerPresetMinutes(_presetMinutes);
    setSleepTimerCustomEnabled(_customEnabled);
    showAppFeedback(context, 'Sleep timer presets updated');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sleep timer presets',
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
            Text(
              'Choose how many preset buttons appear in the player, set their durations, and control the custom slider.',
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Number of presets',
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(6, (index) {
                final int count = index + 1;
                final selected = _presetCount == count;
                return GestureDetector(
                  onTap: () => _applyPresetCount(count),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? palette.accent : palette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? palette.accent : palette.border,
                      ),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: selected ? readableTextOn(palette.accent) : palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            Text(
              'Preset durations',
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _presetCount,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Text(
                          'Preset ${index + 1}',
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 120,
                            divisions: 119,
                            value: _presetMinutes[index].toDouble(),
                            activeColor: palette.accent,
                            inactiveColor: palette.border,
                            label: formatSleepTimerPresetLabel(_presetMinutes[index]),
                            onChanged: (value) {
                              setState(() {
                                _presetMinutes[index] = value.round();
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            formatSleepTimerPresetLabel(_presetMinutes[index]),
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
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          'Custom timer',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Show the custom slider in the player sleep timer',
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CupertinoSwitch(
                    value: _customEnabled,
                    activeTrackColor: palette.accent,
                    onChanged: (value) {
                      setState(() => _customEnabled = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
                  'Save presets',
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
