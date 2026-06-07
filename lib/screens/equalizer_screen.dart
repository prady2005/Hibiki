import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_service.dart';
import '../services/equalizer_settings.dart';
import '../services/theme_state.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  AndroidEqualizerParameters? _parameters;

  @override
  void initState() {
    super.initState();
    _loadParameters();
    currentTrackRevisionNotifier.addListener(_loadParameters);
  }

  @override
  void dispose() {
    currentTrackRevisionNotifier.removeListener(_loadParameters);
    super.dispose();
  }

  Future<void> _loadParameters() async {
    try {
      final AndroidEqualizerParameters parameters = await playbackEqualizer.parameters;
      if (!mounted) return;
      setState(() => _parameters = parameters);
      await applyEqualizerSettings();
    } catch (_) {
      if (!mounted) return;
      setState(() => _parameters = null);
    }
  }

  Future<void> _selectPreset(EqualizerPreset preset) async {
    await applyEqualizerPreset(preset);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onBandChanged(int bandIndex, double gain) async {
    await setCustomEqualizerBandGain(bandIndex, gain);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppThemePalette palette = activeAppPalette(context);
    final AndroidEqualizerParameters? parameters = _parameters;

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
                    'Equalizer',
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
            const SizedBox(height: 8),
            Text(
              'Shape the sound with presets or fine-tune each frequency band.',
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            if (parameters == null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  'Equalizer controls are available on Android. Start playing a song, then return here to adjust bands.',
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 210,
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final AndroidEqualizerBand band in parameters.bands)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.mutedText,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 128,
                                child: StreamBuilder<double>(
                                  stream: band.gainStream,
                                  builder: (context, snapshot) {
                                    return _VerticalEqSlider(
                                      min: parameters.minDecibels,
                                      max: parameters.maxDecibels,
                                      value: snapshot.data ?? band.gain,
                                      activeColor: palette.accent,
                                      inactiveColor: palette.border,
                                      onChanged: (value) =>
                                          _onBandChanged(band.index, value),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatFrequency(band.centerFrequency),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Presets',
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<EqualizerPreset>(
              valueListenable: equalizerPresetNotifier,
              builder: (context, selectedPreset, _) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: EqualizerPreset.values.map((preset) {
                    final selected = selectedPreset == preset;
                    return GestureDetector(
                      onTap: () => _selectPreset(preset),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? palette.accent : palette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? palette.accent : palette.border,
                          ),
                        ),
                        child: Text(
                          equalizerPresetLabel(preset),
                          style: TextStyle(
                            color: selected
                                ? readableTextOn(palette.accent)
                                : palette.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatFrequency(double frequency) {
    if (frequency >= 1000) {
      final double kilohertz = frequency / 1000;
      return kilohertz >= 10
          ? '${kilohertz.round()}k'
          : '${kilohertz.toStringAsFixed(1)}k';
    }
    return '${frequency.round()}';
  }
}

class _VerticalEqSlider extends StatelessWidget {
  const _VerticalEqSlider({
    required this.min,
    required this.max,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.onChanged,
  });

  final double min;
  final double max;
  final double value;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double> onChanged;

  static const double _trackThickness = 26;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double trackLength = constraints.maxHeight.clamp(72.0, 128.0);

        return Center(
          child: SizedBox(
            width: _trackThickness,
            height: trackLength,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: activeColor,
                  inactiveTrackColor: inactiveColor.withOpacity(0.35),
                  thumbColor: activeColor,
                ),
                child: SizedBox(
                  width: trackLength,
                  height: _trackThickness,
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
