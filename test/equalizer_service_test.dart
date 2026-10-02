import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/equalizer_service.dart';

void main() {
  test('the phone\'s equalizer answer becomes bands and gain limits', () {
    EqualizerParameters parameters = EqualizerParameters.fromMap({
      'minDb': -15,
      'maxDb': 15.0,
      'bands': [
        {'index': 0, 'hertz': 60.0, 'gain': 0},
        {'index': 1, 'hertz': 230.0, 'gain': 3.5},
      ],
    });

    expect(parameters.minDb, -15.0);
    expect(parameters.maxDb, 15.0);
    expect(parameters.bands, hasLength(2));
    expect(parameters.bands[1].hertz, 230.0);
    expect(parameters.bands[1].gain, 3.5);
  });
}
