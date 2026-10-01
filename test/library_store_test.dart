import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/library_store.dart';
import 'package:m6player/services/track_info.dart';

void main() {
  late Directory temp;
  late File storeFile;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('m6player_store');
    storeFile = File('${temp.path}/library.json');
  });

  tearDown(() => temp.delete(recursive: true));

  test('favourites, playlists and the sort order are saved and loaded again', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    await store.setSort(SortOrder.artist);
    await store.toggleFavourite('a.mp3');
    Playlist party = await store.createPlaylist('  Party  ');
    await store.addToPlaylist(party.id, 'b.mp3');
    await store.addToPlaylist(party.id, 'a.mp3');

    LibraryStore reopened = await LibraryStore.open(storeFile);

    expect(reopened.sort, SortOrder.artist);
    expect(reopened.isFavourite('a.mp3'), isTrue);
    expect(reopened.isFavourite('b.mp3'), isFalse);
    expect(reopened.playlists.single.name, 'Party');
    expect(reopened.playlists.single.songs, ['b.mp3', 'a.mp3']);
  });

  test('a song is added to a playlist only once', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    Playlist list = await store.createPlaylist('Mix');

    expect(await store.addToPlaylist(list.id, 'a.mp3'), isTrue);
    expect(await store.addToPlaylist(list.id, 'a.mp3'), isFalse);
    expect(store.playlist(list.id)!.songs, ['a.mp3']);
  });

  test('toggling a favourite twice removes it', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    await store.toggleFavourite('a.mp3');
    await store.toggleFavourite('a.mp3');

    expect(store.isFavourite('a.mp3'), isFalse);
  });

  test('renaming keeps the playlist id; deleting removes it', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    Playlist list = await store.createPlaylist('Old');

    await store.renamePlaylist(list.id, 'New');
    expect(store.playlist(list.id)!.name, 'New');

    await store.deletePlaylist(list.id);
    expect(store.playlists, isEmpty);
  });

  test('a deleted song leaves favourites and every playlist', () async {
    LibraryStore store = await LibraryStore.open(storeFile);
    Playlist one = await store.createPlaylist('One');
    Playlist two = await store.createPlaylist('Two');
    await store.toggleFavourite('gone.mp3');
    await store.addToPlaylist(one.id, 'gone.mp3');
    await store.addToPlaylist(two.id, 'gone.mp3');
    await store.addToPlaylist(two.id, 'kept.mp3');

    await store.forgetSong('gone.mp3');

    expect(store.isFavourite('gone.mp3'), isFalse);
    expect(store.playlist(one.id)!.songs, isEmpty);
    expect(store.playlist(two.id)!.songs, ['kept.mp3']);
  });

  test('a damaged file starts an empty library instead of crashing', () async {
    storeFile.writeAsStringSync('{not json');

    LibraryStore store = await LibraryStore.open(storeFile);

    expect(store.sort, SortOrder.dateAdded);
    expect(store.playlists, isEmpty);
  });

  group('sortSongs', () {
    // Oldest first, as the library loads them.
    List<File> songs = [File('/m/c.mp3'), File('/m/a.mp3'), File('/m/b.mp3'), File('/m/d.mp3')];
    Map<String, TrackInfo> tags = {
      '/m/c.mp3': TrackInfo(title: 'Zebra', artist: 'Bien'),
      '/m/a.mp3': TrackInfo(title: 'apple', artist: 'Sauti Sol'),
      '/m/b.mp3': TrackInfo(title: 'Mango'), // No artist
      '/m/d.mp3': TrackInfo(title: 'Banana', artist: 'bien'),
    };
    TrackInfo info(File file) => tags[file.path]!;
    List<String> names(List<File> files) => files.map((f) => f.uri.pathSegments.last).toList();

    test('date added keeps the library order', () {
      expect(names(sortSongs(songs, SortOrder.dateAdded, info)), ['c.mp3', 'a.mp3', 'b.mp3', 'd.mp3']);
    });

    test('title ignores case', () {
      expect(names(sortSongs(songs, SortOrder.title, info)), ['a.mp3', 'd.mp3', 'b.mp3', 'c.mp3']);
    });

    test('artist ignores case, then sorts by title; songs with no artist go last', () {
      expect(names(sortSongs(songs, SortOrder.artist, info)), ['d.mp3', 'c.mp3', 'a.mp3', 'b.mp3']);
    });
  });
}
