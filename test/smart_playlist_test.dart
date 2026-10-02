import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/screens/smart_playlist_screen.dart';
import 'package:m6player/services/library_store.dart';

void main() {
  late Directory temp;
  late File storeFile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('m6player_smart');
    storeFile = File('${temp.path}/library.json');
  });

  tearDown(() => temp.delete(recursive: true));

  test('play counts are saved and loaded again', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    await store.recordPlay('a.mp3');
    await store.recordPlay('a.mp3');

    LibraryStore reopened = await LibraryStore.open(storeFile);

    expect(reopened.playCount('a.mp3'), 2);
    expect(reopened.playCount('b.mp3'), 0);
    expect(reopened.lastPlayed('a.mp3'), isNotNull);
    expect(reopened.lastPlayed('b.mp3'), isNull);
  });

  test('smart playlists pick and order songs', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    await store.recordPlay('b');
    await store.recordPlay('c');
    await store.recordPlay('c');
    List<String> newestFirst = ['a', 'b', 'c', 'd'];
    String same(String key) => key;

    expect(SmartPlaylist.mostPlayed.pick(newestFirst, same, store), ['c', 'b']);
    // Plays within the same millisecond tie, so only which songs are checked here
    expect(SmartPlaylist.recentlyPlayed.pick(newestFirst, same, store), unorderedEquals(['c', 'b']));
    expect(SmartPlaylist.recentlyAdded.pick(newestFirst, same, store), newestFirst);
    expect(SmartPlaylist.neverPlayed.pick(newestFirst, same, store), ['a', 'd']);
  });

  test('a backup restores play counts and rejects other files', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    await store.recordPlay('a.mp3');
    String backup = store.backupJson();

    File other = File('${temp.path}/other.json');
    LibraryStore fresh = await LibraryStore.open(other);
    await fresh.restoreFrom(backup);

    expect(fresh.playCount('a.mp3'), 1);
    expect(() => fresh.restoreFrom('{"hello": 1}'), throwsFormatException);
  });
}
