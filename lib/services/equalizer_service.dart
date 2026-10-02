import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'app_settings.dart';

/// One frequency band of the equalizer.
class EqBand {
  final int index;
  final double hertz;
  final double gain; // dB when read from the phone

  const EqBand({required this.index, required this.hertz, required this.gain});
}

/// What the phone's equalizer offers: the gain limits and its bands.
class EqualizerParameters {
  final double minDb;
  final double maxDb;
  final List<EqBand> bands;

  const EqualizerParameters({required this.minDb, required this.maxDb, required this.bands});

  /// Reads the answer the native side (EqualizerBridge.java) sends.
  static EqualizerParameters fromMap(Map<dynamic, dynamic> map) => EqualizerParameters(
        minDb: (map['minDb'] as num).toDouble(),
        maxDb: (map['maxDb'] as num).toDouble(),
        bands: [
          for (Map<dynamic, dynamic> band in (map['bands'] as List).cast<Map<dynamic, dynamic>>())
            EqBand(
              index: (band['index'] as num).toInt(),
              hertz: (band['hertz'] as num).toDouble(),
              gain: (band['gain'] as num).toDouble(),
            ),
        ],
      );
}

/// The equalizer (Android). The native side attaches it to the player's audio
/// session; this follows the session id (it changes whenever the player starts
/// afresh), and passes on the on/off switch and band gains, which are saved in
/// [AppSettings] and applied to every new session. Playback never waits for it.
class EqualizerService {
  EqualizerService._();
  static final EqualizerService instance = EqualizerService._();

  static const MethodChannel _channel = MethodChannel('com.msixv.com.m6player/equalizer');

  /// The phone's equalizer once something has played (null before that, or if the phone has none).
  final ValueNotifier<EqualizerParameters?> parameters = ValueNotifier(null);

  StreamSubscription<int?>? _session;

  /// Starts following [player]: hands the saved settings to the native side,
  /// then attaches the equalizer to each audio session the player gets.
  void start(AudioPlayer player) {
    if (_session != null || !Platform.isAndroid) return;
    AppSettings settings = AppSettings.instance;
    _call('configure', {'enabled': settings.equalizerOn, 'gains': settings.equalizerGains});
    _session = player.androidAudioSessionIdStream.distinct().listen((id) async {
      if (id == null) return;
      Object? answer = await _call('attach', {'sessionId': id});
      parameters.value = answer is Map ? EqualizerParameters.fromMap(answer) : null;
    });
  }

  Future<void> setEnabled(bool on) => _call('setEnabled', {'enabled': on});

  Future<void> setGain(int band, double gainDb) => _call('setGain', {'band': band, 'gain': gainDb});

  Future<Object?> _call(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } catch (e) {
      debugPrint("Equalizer $method failed: $e"); // Only the equalizer is affected
      return null;
    }
  }
}
