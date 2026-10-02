import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// App settings: light/dark mode and the equalizer, saved as settings.json in
/// the app's folder. Load once at start-up ([load]); until then (and in tests)
/// the defaults apply.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  File? _file;
  ThemeMode _themeMode = ThemeMode.system;
  bool _equalizerOn = false;
  String _equalizerPreset = 'Flat';
  List<double> _equalizerGains = []; // dB per band, lowest frequency first
  bool _onboarded = false; // The first-run pages have been seen
  String? _radioCountry; // ISO code chosen in Radio; null follows the phone's region
  String? _pinSalt; // The Hidden page's PIN is kept only as a salted hash
  String? _pinHash;

  ThemeMode get themeMode => _themeMode;
  bool get equalizerOn => _equalizerOn;
  String get equalizerPreset => _equalizerPreset;
  bool get onboarded => _onboarded;
  String? get radioCountry => _radioCountry;
  bool get hasPin => _pinHash != null;
  List<double> get equalizerGains => List.unmodifiable(_equalizerGains);

  /// Reads the saved settings (or keeps the defaults if there are none).
  Future<void> load({File? file}) async {
    try {
      _file = file ?? File('${(await getApplicationDocumentsDirectory()).path}/settings.json');
      if (!await _file!.exists()) return;
      Map<String, dynamic> json = jsonDecode(await _file!.readAsString());
      _themeMode = ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system;
      _equalizerOn = json['equalizerOn'] == true;
      _equalizerPreset = json['equalizerPreset'] as String? ?? 'Flat';
      _equalizerGains = (json['equalizerGains'] as List? ?? []).map((g) => (g as num).toDouble()).toList();
      _onboarded = json['onboarded'] == true;
      _radioCountry = json['radioCountry'] as String?;
      _pinSalt = json['pinSalt'] as String?;
      _pinHash = json['pinHash'] as String?;
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading settings: $e"); // Keep the defaults
    }
  }

  Future<void> _save() async {
    notifyListeners();
    File? file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode({
        'themeMode': _themeMode.name,
        'equalizerOn': _equalizerOn,
        'equalizerPreset': _equalizerPreset,
        'equalizerGains': _equalizerGains,
        'onboarded': _onboarded,
        'radioCountry': _radioCountry,
        'pinSalt': _pinSalt,
        'pinHash': _pinHash,
      }));
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _save();
  }

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  bool checkPin(String pin) => _pinHash == null || _hash(_pinSalt ?? '', pin) == _pinHash;

  /// Sets the Hidden page's PIN; null removes it.
  Future<void> setPin(String? pin) async {
    if (pin == null) {
      _pinSalt = null;
      _pinHash = null;
    } else {
      _pinSalt = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16)).join();
      _pinHash = _hash(_pinSalt!, pin);
    }
    await _save();
  }

  Future<void> setOnboarded() async {
    _onboarded = true;
    await _save();
  }

  Future<void> setRadioCountry(String? code) async {
    _radioCountry = code;
    await _save();
  }

  Future<void> setEqualizerOn(bool on) async {
    _equalizerOn = on;
    await _save();
  }

  /// Saves the band gains and which preset they came from ("Custom" for hand-set).
  Future<void> setEqualizerGains(List<double> gains, {required String preset}) async {
    _equalizerGains = List.of(gains);
    _equalizerPreset = preset;
    await _save();
  }
}

/// Equalizer presets: the gain (dB) for a band centred on [hertz], before
/// limiting to what the phone's equalizer allows.
const List<String> equalizerPresets = ['Flat', 'Bass boost', 'Treble boost', 'Vocal', 'Rock', 'Pop', 'Jazz', 'Classical'];

double presetGain(String preset, double hertz) {
  bool low = hertz <= 250, lowMid = hertz > 250 && hertz <= 1000, highMid = hertz > 1000 && hertz <= 4000;
  bool high = hertz > 4000;
  switch (preset) {
    case 'Bass boost':
      return low ? 6 : (lowMid ? 2 : 0);
    case 'Treble boost':
      return high ? 6 : (highMid ? 3 : 0);
    case 'Vocal':
      return low ? -2 : (lowMid || highMid ? 4 : 1);
    case 'Rock':
      return low ? 5 : (lowMid ? -1 : (highMid ? 2 : 4));
    case 'Pop':
      return low ? -1 : (lowMid ? 3 : (highMid ? 4 : 2));
    case 'Jazz':
      return low ? 3 : (lowMid ? 1 : (highMid ? 2 : 3));
    case 'Classical':
      return low ? 4 : (lowMid ? 0 : (highMid ? 1 : 3));
    default: // Flat
      return 0;
  }
}
