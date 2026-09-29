import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/player_service.dart';
import 'package:m6player/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('pads minutes and seconds', () {
      expect(formatDuration(Duration.zero), '00:00');
      expect(formatDuration(Duration(minutes: 3, seconds: 7)), '03:07');
    });

    test('shows hours for long durations', () {
      expect(formatDuration(Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });
  });

  group('trackTitle', () {
    test('strips directory and extension', () {
      expect(trackTitle(File('/music/My Song.mp3')), 'My Song');
      expect(trackTitle(File('/music/a.b.mp3')), 'a.b');
    });

    test('keeps names without an extension', () {
      expect(trackTitle(File('/music/README')), 'README');
    });
  });
}
