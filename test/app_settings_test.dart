import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/app_settings.dart';

void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('m6player_settings'));
  tearDown(() => temp.delete(recursive: true));

  test('settings are written to the file', () async {
    File file = File('${temp.path}/settings.json');
    AppSettings settings = AppSettings.instance;
    await settings.load(file: file); // No file yet: defaults
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setEqualizerOn(true);
    await settings.setEqualizerGains([3, -1.5, 0, 2, 6], preset: 'Custom');

    Map<String, dynamic> saved = jsonDecode(file.readAsStringSync());
    expect(saved['themeMode'], 'dark');
    expect(saved['equalizerOn'], isTrue);
    expect(saved['equalizerPreset'], 'Custom');
    expect(saved['equalizerGains'], [3, -1.5, 0, 2, 6]);
  });

  test('saved settings are read back at start-up', () async {
    File file = File('${temp.path}/settings.json')
      ..writeAsStringSync(jsonEncode({
        'themeMode': 'light',
        'equalizerOn': false,
        'equalizerPreset': 'Rock',
        'equalizerGains': [5, -1, 2, 4],
      }));
    AppSettings settings = AppSettings.instance;
    await settings.load(file: file);

    expect(settings.themeMode, ThemeMode.light);
    expect(settings.equalizerOn, isFalse);
    expect(settings.equalizerPreset, 'Rock');
    expect(settings.equalizerGains, [5, -1, 2, 4]);
  });

  test('presets shape the right frequencies', () {
    expect(presetGain('Flat', 60), 0);
    expect(presetGain('Bass boost', 60), greaterThan(presetGain('Bass boost', 14000)));
    expect(presetGain('Treble boost', 14000), greaterThan(presetGain('Treble boost', 60)));
    expect(presetGain('Vocal', 1000), greaterThan(presetGain('Vocal', 60)));
    for (String preset in equalizerPresets) {
      expect(presetGain(preset, 1000).abs(), lessThanOrEqualTo(6), reason: preset);
    }
  });
}
