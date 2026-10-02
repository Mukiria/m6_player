import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'library_store.dart';
import 'music_library.dart';
import 'player_service.dart';
import 'radio_api.dart';
import 'track_info.dart';

/// What Android Auto can browse and play: a short menu of Songs, Favourites,
/// Playlists and Radio favourites. The car draws the screens; this supplies the
/// lists and starts playback. Used by [M6AudioHandler].
///
/// Item ids: folders are `songs`, `favourites`, `playlists`, `radio` and
/// `playlist:<id>`; playable items are `song/<list>/<file name>` and
/// `station:<stream url>`.
class CarBrowser {
  CarBrowser._();

  /// Lists in a car stay short: head units cap how much they show anyway.
  static const int maxItems = 100;

  static const String songsId = 'songs';
  static const String favouritesId = 'favourites';
  static const String playlistsId = 'playlists';
  static const String radioId = 'radio';
  static const String playlistPrefix = 'playlist:';
  static const String stationPrefix = 'station:';

  static String songItemId(String list, String key) => 'song/$list/$key';

  /// The list and file name inside a song item id, or null if it isn't one.
  static (String, String)? parseSongId(String id) {
    if (!id.startsWith('song/')) return null;
    int slash = id.indexOf('/', 5);
    if (slash < 0) return null;
    return (id.substring(5, slash), id.substring(slash + 1));
  }

  static MediaItem _folder(String id, String title, {String? subtitle}) =>
      MediaItem(id: id, title: title, displaySubtitle: subtitle, playable: false);

  /// The folder's contents.
  static Future<List<MediaItem>> children(String parentId) async {
    try {
      LibraryStore store = await LibraryStore.instance();
      switch (parentId) {
        case AudioService.browsableRootId:
          return [
            _folder(songsId, "Songs"),
            _folder(favouritesId, "Favourites"),
            _folder(playlistsId, "Playlists"),
            _folder(radioId, "Radio favourites"),
          ];
        case playlistsId:
          return [
            for (Playlist playlist in store.playlistsOf(MediaKind.audio).take(maxItems))
              _folder('$playlistPrefix${playlist.id}', playlist.name,
                  subtitle: "${playlist.songs.length} ${playlist.songs.length == 1 ? "song" : "songs"}"),
          ];
        case radioId:
          return [for (RadioStation station in store.radioFavourites.take(maxItems)) _station(station)];
        default:
          List<File>? songs = await songsOf(parentId, store);
          if (songs == null) return [];
          String list = parentId;
          return [for (File song in songs) _song(list, song)];
      }
    } catch (e) {
      debugPrint("Error building the car menu: $e");
      return [];
    }
  }

  /// The songs in a song folder (not hidden, at most [maxItems]); null if [folderId] isn't one.
  static Future<List<File>?> songsOf(String folderId, LibraryStore store) async {
    MusicLibrary library = MusicLibrary.instance;
    await library.load();
    bool visible(File song) => !store.isHidden(songKey(song));
    List<File> songs;
    if (folderId == songsId) {
      // Newest first, and not filtered out of the Songs list
      songs = library.songs.reversed.where((s) => visible(s) && !store.isFilteredOut(songKey(s))).toList();
    } else if (folderId == favouritesId) {
      songs = library.songs.reversed.where((s) => visible(s) && store.isFavourite(songKey(s))).toList();
    } else if (folderId.startsWith(playlistPrefix)) {
      Playlist? playlist = store.playlist(folderId.substring(playlistPrefix.length));
      if (playlist == null) return null;
      songs = playlist.songs.map(library.songNamed).whereType<File>().where(visible).toList();
    } else {
      return null;
    }
    return songs.take(maxItems).toList();
  }

  static MediaItem _song(String list, File file) {
    TrackInfo info = TrackInfoService.instance.infoFor(file);
    return MediaItem(
      id: songItemId(list, songKey(file)),
      title: info.title,
      artist: info.artist,
      album: info.album,
      duration: info.duration,
    );
  }

  static MediaItem _station(RadioStation station) => MediaItem(
        id: '$stationPrefix${station.url}',
        title: station.name,
        album: 'Radio',
        isLive: true,
        extras: {'radio': true},
      );

  /// One item by id (the car asks this when resuming).
  static Future<MediaItem?> item(String id) async {
    try {
      LibraryStore store = await LibraryStore.instance();
      (String, String)? song = parseSongId(id);
      if (song != null) {
        await MusicLibrary.instance.load();
        File? file = MusicLibrary.instance.songNamed(song.$2);
        return file == null ? null : _song(song.$1, file);
      }
      if (id.startsWith(stationPrefix)) {
        String url = id.substring(stationPrefix.length);
        RadioStation? station = store.radioFavourites.where((s) => s.url == url).firstOrNull;
        return station == null ? null : _station(station);
      }
    } catch (e) {
      debugPrint("Error finding a car item: $e");
    }
    return null;
  }

  /// Plays the tapped song with the rest of its list after it, or the station.
  static Future<void> play(String id) async {
    PlayerService player = PlayerService.instance;
    LibraryStore store = await LibraryStore.instance();
    (String, String)? song = parseSongId(id);
    if (song != null) {
      List<File>? songs = await songsOf(song.$1, store);
      if (songs == null) return;
      int index = songs.indexWhere((file) => songKey(file) == song.$2);
      if (index < 0) return;
      await player.playQueue('car:${song.$1}', songs, index);
    } else if (id.startsWith(stationPrefix)) {
      String url = id.substring(stationPrefix.length);
      RadioStation? station = store.radioFavourites.where((s) => s.url == url).firstOrNull;
      if (station != null) await player.playStream(station.url, station.name);
    }
  }

  /// Voice search ("play Sauti Sol"): plays the songs whose title, artist or album matches.
  static Future<void> playSearch(String query) async {
    String text = query.trim().toLowerCase();
    LibraryStore store = await LibraryStore.instance();
    MusicLibrary library = MusicLibrary.instance;
    await library.load();
    List<File> matches = library.songs.reversed.where((song) {
      if (store.isHidden(songKey(song))) return false;
      if (text.isEmpty) return true; // "Play music": anything
      TrackInfo info = TrackInfoService.instance.infoFor(song);
      return [info.title, info.artist, info.album].any((field) => field?.toLowerCase().contains(text) ?? false);
    }).take(maxItems).toList();
    if (matches.isEmpty) return;
    await PlayerService.instance.playQueue('car:search', matches, 0);
  }
}
