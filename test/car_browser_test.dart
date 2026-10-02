import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/car_browser.dart';

void main() {
  group('car item ids', () {
    test('a song id round-trips its list and file name', () {
      String id = CarBrowser.songItemId('favourites', 'My Song.mp3');

      expect(CarBrowser.parseSongId(id), ('favourites', 'My Song.mp3'));
    });

    test('a playlist list id and a file name with a colon survive', () {
      String id = CarBrowser.songItemId('playlist:123', 'a: b.mp3');

      expect(CarBrowser.parseSongId(id), ('playlist:123', 'a: b.mp3'));
    });

    test('ids that are not songs are rejected', () {
      expect(CarBrowser.parseSongId('station:https://x.example/live'), isNull);
      expect(CarBrowser.parseSongId('song/onlylist'), isNull);
      expect(CarBrowser.parseSongId('songs'), isNull);
    });
  });
}
