import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum EqualizerPreset {
  balanced,
  bassBoost,
  smooth,
  dynamic,
  clear,
  trebleBoost,
  custom,
}

final equalizerPresetNotifier = ValueNotifier<EqualizerPreset>(
  EqualizerPreset.balanced,
);
final customEqualizerGainsNotifier = ValueNotifier<List<double>>(<double>[]);

String equalizerPresetLabel(EqualizerPreset preset) {
  switch (preset) {
    case EqualizerPreset.balanced:
      return 'Balanced';
    case EqualizerPreset.bassBoost:
      return 'Bass boost';
    case EqualizerPreset.smooth:
      return 'Smooth';
    case EqualizerPreset.dynamic:
      return 'Dynamic';
    case EqualizerPreset.clear:
      return 'Clear';
    case EqualizerPreset.trebleBoost:
      return 'Treble boost';
    case EqualizerPreset.custom:
      return 'Custom';
  }
}

double _bandPosition(int index, int bandCount) {
  if (bandCount <= 1) return 0.5;
  return index / (bandCount - 1);
}

List<double> equalizerGainsForPreset(EqualizerPreset preset, int bandCount) {
  if (preset == EqualizerPreset.custom) {
    final custom = List<double>.from(customEqualizerGainsNotifier.value);
    while (custom.length < bandCount) {
      custom.add(0);
    }
    if (custom.length > bandCount) {
      return custom.take(bandCount).toList();
    }
    return custom;
  }

  return List<double>.generate(bandCount, (index) {
    final double position = _bandPosition(index, bandCount);
    switch (preset) {
      case EqualizerPreset.balanced:
        return 0;
      case EqualizerPreset.bassBoost:
        return 6 * (1 - position) - 1.5 * position;
      case EqualizerPreset.trebleBoost:
        return 6 * position - 1.5 * (1 - position);
      case EqualizerPreset.smooth:
        return 1.5 * (1 - position) - 3.5 * position * position;
      case EqualizerPreset.dynamic:
        return 5 * (1 - math.sin(position * math.pi));
      case EqualizerPreset.clear:
        final double midBell = math.exp(-math.pow((position - 0.5) * 2.8, 2)) * 5;
        return midBell - 1.5 * position;
      case EqualizerPreset.custom:
        return 0;
    }
  });
}

void storeCustomEqualizerGains(List<double> gains) {
  customEqualizerGainsNotifier.value = List<double>.from(gains);
}
