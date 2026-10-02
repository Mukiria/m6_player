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

  group('car lists', () {
    test('a list name with a slash in it still round-trips', () {
      String id = CarBrowser.songItemId('album:AC/DC', 'Back In Black.mp3');

      expect(CarBrowser.parseSongId(id), ('album:AC/DC', 'Back In Black.mp3'));
    });

    test('a car that does not page gets the first 100, and one that does gets its page', () {
      List<int> items = List.generate(250, (i) => i);

      expect(CarBrowser.page(items, null), items.take(100).toList());
      expect(CarBrowser.page(items, {'android.media.browse.extra.PAGE': 1, 'android.media.browse.extra.PAGE_SIZE': 100}),
          items.sublist(100, 200));
      expect(CarBrowser.page(items, {'android.media.browse.extra.PAGE': 2, 'android.media.browse.extra.PAGE_SIZE': 100}),
          items.sublist(200, 250));
      expect(CarBrowser.page(items, {'android.media.browse.extra.PAGE': 3, 'android.media.browse.extra.PAGE_SIZE': 100}),
          isEmpty);
    });

    test('a cover becomes a content address the car can fetch', () {
      Uri? uri = CarBrowser.coverUri('/data/user/0/com.msixv.com.m6player/app_flutter/covers/My Song.mp3.jpg');

      expect(uri.toString(), 'content://com.msixv.com.m6player.covers/My%20Song.mp3.jpg');
      expect(uri!.pathSegments.single, 'My Song.mp3.jpg');
      expect(CarBrowser.coverUri(null), isNull);
    });
  });
}
