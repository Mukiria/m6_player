import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/player_service.dart';

void main() {
  Duration s(int seconds) => Duration(seconds: seconds);
  const Duration song = Duration(minutes: 3);

  test('crossfade off leaves the volume alone', () {
    expect(PlayerService.fadeFactor(s(1), song, 0, fadeOut: true), 1.0);
  });

  test('the start fades in and the end fades out over the chosen seconds', () {
    expect(PlayerService.fadeFactor(Duration.zero, song, 6, fadeOut: true), 0.0);
    expect(PlayerService.fadeFactor(s(3), song, 6, fadeOut: true), closeTo(0.5, 0.001));
    expect(PlayerService.fadeFactor(s(60), song, 6, fadeOut: true), 1.0);
    expect(PlayerService.fadeFactor(s(177), song, 6, fadeOut: true), closeTo(0.5, 0.001));
    expect(PlayerService.fadeFactor(song, song, 6, fadeOut: true), 0.0);
  });

  test('the last song of a list does not fade out', () {
    expect(PlayerService.fadeFactor(s(179), song, 6, fadeOut: false), 1.0);
  });

  test('a short song gets shorter fades so they never overlap', () {
    Duration short = s(10);
    // 12 s fades would not fit: they shrink to 4 s (10 s / 2.5)
    expect(PlayerService.fadeFactor(s(2), short, 12, fadeOut: true), closeTo(0.5, 0.001));
    expect(PlayerService.fadeFactor(s(5), short, 12, fadeOut: true), 1.0);
  });

  test('an unknown length leaves the volume alone', () {
    expect(PlayerService.fadeFactor(s(1), null, 6, fadeOut: true), 1.0);
  });
}
