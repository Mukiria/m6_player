import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/app_settings.dart';
import '../services/player_service.dart';

/// The equalizer (Android): an on/off switch, presets, and a slider per
/// frequency band. Settings are saved and applied every time the app plays.
/// Android only makes the equalizer available once something has played, so
/// until then the screen asks the user to start a song or station.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final AndroidEqualizer _equalizer = PlayerService.instance.equalizer;
  final AppSettings _settings = AppSettings.instance;
  AndroidEqualizerParameters? _parameters;
  late List<double> _gains; // What the sliders show, dB per band

  @override
  void initState() {
    super.initState();
    _gains = [];
    _equalizer.parameters.then((parameters) {
      if (!mounted) return;
      setState(() {
        _parameters = parameters;
        _gains = [for (AndroidEqualizerBand band in parameters.bands) band.gain];
      });
    });
  }

  Future<void> _setOn(bool on) async {
    await _equalizer.setEnabled(on);
    await _settings.setEqualizerOn(on);
    setState(() {});
  }

  Future<void> _applyPreset(String preset) async {
    AndroidEqualizerParameters? parameters = _parameters;
    if (parameters == null) return;
    List<double> gains = [
      for (AndroidEqualizerBand band in parameters.bands)
        presetGain(preset, band.centerFrequency) // just_audio gives hertz
            .clamp(parameters.minDecibels, parameters.maxDecibels)
            .toDouble(),
    ];
    for (AndroidEqualizerBand band in parameters.bands) {
      await band.setGain(gains[band.index]);
    }
    if (!_settings.equalizerOn) await _setOn(true); // Choosing a preset turns it on
    await _settings.setEqualizerGains(gains, preset: preset);
    setState(() => _gains = gains);
  }

  Future<void> _setBand(AndroidEqualizerBand band, double gain, {bool save = false}) async {
    setState(() => _gains[band.index] = gain);
    await band.setGain(gain);
    if (save) await _settings.setEqualizerGains(_gains, preset: 'Custom');
  }

  /// "60 Hz", "1.2 kHz" (just_audio gives band frequencies in hertz).
  String _frequency(double hertz) {
    return hertz >= 1000 ? "${(hertz / 1000).toStringAsFixed(hertz >= 10000 ? 0 : 1)} kHz" : "${hertz.round()} Hz";
  }

  /// Crossfade length between songs. Works whether or not the equalizer is available yet.
  Widget _crossfadeSection(ColorScheme colors) {
    int seconds = _settings.crossfadeSeconds;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text("Crossfade", style: TextStyle(fontWeight: FontWeight.w600))),
              Text(seconds == 0 ? "Off" : "$seconds s", style: TextStyle(color: colors.primary)),
            ],
          ),
          Slider(
            value: seconds.toDouble(),
            max: 12,
            divisions: 12,
            label: seconds == 0 ? "Off" : "$seconds s",
            onChanged: (value) async {
              await _settings.setCrossfadeSeconds(value.round());
              if (mounted) setState(() {});
            },
          ),
          Text(
            "Fades a song out at its end and the next one in. Songs only (not radio). "
            "It dips through quiet rather than overlapping the two songs.",
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    AndroidEqualizerParameters? parameters = _parameters;
    bool on = _settings.equalizerOn;
    return Scaffold(
      appBar: AppBar(title: Text("Equalizer")),
      body: parameters == null
          ? ListView(
              children: [
                _crossfadeSection(colors),
                Divider(),
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.equalizer, size: 64, color: colors.onSurfaceVariant),
                      SizedBox(height: 16),
                      Text(
                        "Play a song or a radio station, then come back here to adjust the equalizer.",
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              padding: EdgeInsets.symmetric(vertical: 8),
              children: [
                _crossfadeSection(colors),
                Divider(),
                SwitchListTile(
                  title: Text("Equalizer"),
                  subtitle: Text(on ? "On · ${_settings.equalizerPreset}" : "Off"),
                  value: on,
                  onChanged: _setOn,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text("Presets", style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (String preset in equalizerPresets)
                        ChoiceChip(
                          label: Text(preset),
                          selected: on && _settings.equalizerPreset == preset,
                          onSelected: (_) => _applyPreset(preset),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                // One vertical slider per band, low frequencies on the left.
                Opacity(
                  opacity: on ? 1 : 0.45,
                  child: SizedBox(
                    height: 260,
                    child: Row(
                      children: [
                        for (AndroidEqualizerBand band in parameters.bands)
                          Expanded(
                            child: Column(
                              children: [
                                Text("${_gains[band.index] > 0 ? "+" : ""}${_gains[band.index].toStringAsFixed(0)} dB",
                                    style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                                Expanded(
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: Slider(
                                      value: _gains[band.index],
                                      min: parameters.minDecibels,
                                      max: parameters.maxDecibels,
                                      onChanged: on ? (gain) => _setBand(band, gain) : null,
                                      onChangeEnd: on ? (gain) => _setBand(band, gain, save: true) : null,
                                    ),
                                  ),
                                ),
                                Text(_frequency(band.centerFrequency), style: TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: on ? () => _applyPreset('Flat') : null,
                    icon: Icon(Icons.restart_alt),
                    label: Text("Reset to flat"),
                  ),
                ),
              ],
            ),
    );
  }
}
