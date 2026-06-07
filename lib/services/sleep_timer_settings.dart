import 'package:flutter/foundation.dart';

const List<int> defaultSleepTimerPresetMinutes = <int>[10, 15, 30, 45, 60];

final sleepTimerPresetCountNotifier = ValueNotifier<int>(defaultSleepTimerPresetMinutes.length);
final sleepTimerPresetMinutesNotifier = ValueNotifier<List<int>>(
  List<int>.from(defaultSleepTimerPresetMinutes),
);
final sleepTimerCustomEnabledNotifier = ValueNotifier<bool>(true);

String formatSleepTimerPresetLabel(int minutes) {
  if (minutes >= 60 && minutes % 60 == 0) {
    final int hours = minutes ~/ 60;
    return hours == 1 ? '1 hr' : '$hours hr';
  }
  return '$minutes min';
}

List<int> sleepTimerPresetMinutesSnapshot() {
  final int count = sleepTimerPresetCountNotifier.value.clamp(1, 6);
  final presets = List<int>.from(sleepTimerPresetMinutesNotifier.value);
  while (presets.length < count) {
    presets.add(defaultSleepTimerPresetMinutes[presets.length % defaultSleepTimerPresetMinutes.length]);
  }
  return presets.take(count).toList();
}

List<int> sleepTimerPresetMinutesForPlayer() {
  final List<int> uniqueSorted = sleepTimerPresetMinutesSnapshot().toSet().toList()..sort();
  return uniqueSorted;
}

void setSleepTimerPresetCount(int count) {
  final int nextCount = count.clamp(1, 6);
  final List<int> presets = sleepTimerPresetMinutesSnapshot();
  sleepTimerPresetCountNotifier.value = nextCount;
  sleepTimerPresetMinutesNotifier.value = presets.take(nextCount).toList();
}

void updateSleepTimerPresetMinutes(List<int> minutes) {
  sleepTimerPresetMinutesNotifier.value = minutes
      .map((value) => value.clamp(1, 180))
      .toList();
}

void setSleepTimerCustomEnabled(bool enabled) {
  sleepTimerCustomEnabledNotifier.value = enabled;
}
