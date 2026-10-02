import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import '../screens/smart_playlist_screen.dart';
import '../widgets/music_browse.dart';
import 'library_store.dart';
import 'music_library.dart';
import 'player_service.dart';
import 'radio_api.dart';
import 'track_info.dart';

/// What Android Auto can browse and play. The car draws the screens; this
/// supplies the lists and starts playback. Used by [M6AudioHandler].
///
/// The menu:
/// - Recently played
/// - Songs, Favourites
/// - Playlists: the smart playlists, then your own
/// - Browse: Albums, Artists, Genres
/// - Radio: favourite stations, recent stations
///
/// Folder ids: `songs`, `favourites`, `playlists`, `browse`, `radio`, `albums`,
/// `artists`, `genres`, `radio:favourites`, `radio:recent`, `playlist:<id>`,
/// `smart:<name>`, `album:<name>`, `artist:<name>`, `genre:<name>`.
/// Playable ids: `song/<list, URL-encoded>/<file name>` and `station:<stream url>`.
class CarBrowser {
  CarBrowser._();

  /// Items per page when the car doesn't ask for pages itself.
  static const int defaultPage = 100;

  /// A queue holds at most this many songs.
  static const int maxQueue = 1000;

  static const String songsId = 'songs';
  static const String favouritesId = 'favourites';
  static const String playlistsId = 'playlists';
  static const String browseId = 'browse';
  static const String radioId = 'radio';
  static const String albumsId = 'albums';
  static const String artistsId = 'artists';
  static const String genresId = 'genres';
  static const String radioFavouritesId = 'radio:favourites';
  static const String radioRecentId = 'radio:recent';
  static const String recentlyPlayedId = 'smart:recentlyPlayed';
  static const String playlistPrefix = 'playlist:';
  static const String smartPrefix = 'smart:';
  static const String albumPrefix = 'album:';
  static const String artistPrefix = 'artist:';
  static const String genrePrefix = 'genre:';
  static const String stationPrefix = 'station:';
  static const String searchPrefix = 'search:';

  // ------------------------------------------------------------ Ids

  static String songItemId(String list, String key) => 'song/${Uri.encodeComponent(list)}/$key';

  /// The list and file name inside a song item id, or null if it isn't one.
  static (String, String)? parseSongId(String id) {
    if (!id.startsWith('song/')) return null;
    int slash = id.indexOf('/', 5);
    if (slash < 0) return null;
    return (Uri.decodeComponent(id.substring(5, slash)), id.substring(slash + 1));
  }

  // ------------------------------------------------------------ Paging and art

  static const String _pageKey = 'android.media.browse.extra.PAGE';
  static const String _pageSizeKey = 'android.media.browse.extra.PAGE_SIZE';

  /// The slice of [items] the car asked for (its page number and size), or the
  /// first [defaultPage] when it doesn't page.
  static List<T> page<T>(List<T> items, Map<String, dynamic>? options) {
    Object? page = options?[_pageKey];
    Object? size = options?[_pageSizeKey];
    if (page is int && size is int && page >= 0 && size > 0) {
      int start = page * size;
      if (start >= items.length) return [];
      return items.sublist(start, (start + size).clamp(0, items.length));
    }
    return items.take(defaultPage).toList();
  }

  /// Where the car can fetch a cover: our content provider (CoverProvider.java)
  /// serves the saved covers, since the car can't open the app's private files.
  static Uri? coverUri(String? coverPath) {
    if (coverPath == null || coverPath.isEmpty) return null;
    String name = coverPath.split('/').last;
    return Uri(scheme: 'content', host: coverAuthority, pathSegments: [name]);
  }

  static const String coverAuthority = 'com.msixv.com.m6player.covers';

  static Uri? _coverOf(Iterable<File> songs) {
    for (File song in songs) {
      Uri? uri = coverUri(TrackInfoService.instance.infoFor(song).coverPath);
      if (uri != null) return uri;
    }
    return null;
  }

  // ------------------------------------------------------------ Items

  static MediaItem _folder(String id, String title, {String? subtitle, Uri? art}) =>
      MediaItem(id: id, title: title, displaySubtitle: subtitle, artUri: art, playable: false);

  static String _count(int n, String noun) => "$n $noun${n == 1 ? '' : 's'}";

  static MediaItem _song(String list, File file) {
    TrackInfo info = TrackInfoService.instance.infoFor(file);
    return MediaItem(
      id: songItemId(list, songKey(file)),
      title: info.title,
      artist: info.artist,
      album: info.album,
      duration: info.duration,
      artUri: coverUri(info.coverPath),
    );
  }

  static MediaItem _station(RadioStation station) => MediaItem(
        id: '$stationPrefix${station.url}',
        title: station.name,
        album: 'Radio',
        isLive: true,
        extras: {'radio': true},
      );

  // ------------------------------------------------------------ Browsing

  /// The folder's contents.
  static Future<List<MediaItem>> children(String parentId, [Map<String, dynamic>? options]) async {
    try {
      LibraryStore store = await LibraryStore.instance();
      MusicLibrary library = MusicLibrary.instance;
      switch (parentId) {
        case AudioService.browsableRootId:
          return [
            _folder(recentlyPlayedId, "Recently played"),
            _folder(songsId, "Songs"),
            _folder(favouritesId, "Favourites"),
            _folder(playlistsId, "Playlists"),
            _folder(browseId, "Browse"),
            _folder(radioId, "Radio"),
          ];
        case playlistsId:
          await library.load();
          List<MediaItem> all = [
            for (SmartPlaylist smart in SmartPlaylist.values) _folder('$smartPrefix${smart.name}', smart.label, subtitle: smart.description),
            for (Playlist playlist in store.playlistsOf(MediaKind.audio))
              _folder('$playlistPrefix${playlist.id}', playlist.name,
                  subtitle: _count(playlist.songs.length, "song"),
                  art: _coverOf(playlist.songs.map(library.songNamed).whereType<File>())),
          ];
          return page(all, options);
        case browseId:
          return [_folder(albumsId, "Albums"), _folder(artistsId, "Artists"), _folder(genresId, "Genres")];
        case albumsId:
        case artistsId:
        case genresId:
          await library.load();
          return page(_groupFolders(parentId), options);
        case radioId:
          return [_folder(radioFavouritesId, "Favourite stations"), _folder(radioRecentId, "Recent stations")];
        case radioFavouritesId:
          return page([for (RadioStation s in store.radioFavourites) _station(s)], options);
        case radioRecentId:
          return page([for (RadioStation s in store.radioRecent) _station(s)], options);
        default:
          List<File>? songs = await songsOf(parentId, store);
          if (songs == null) return [];
          return page([for (File song in songs) _song(parentId, song)], options);
      }
    } catch (e) {
      debugPrint("Error building the car menu: $e");
      return [];
    }
  }

  /// Albums, artists or genres as folders, A to Z ("unknown" last).
  static List<MediaItem> _groupFolders(String folderId) {
    BrowseBy by = switch (folderId) {
      albumsId => BrowseBy.albums,
      artistsId => BrowseBy.artists,
      _ => BrowseBy.genres,
    };
    String prefix = switch (by) {
      BrowseBy.albums => albumPrefix,
      BrowseBy.artists => artistPrefix,
      BrowseBy.genres => genrePrefix,
    };
    Map<String, List<File>> groups = browseGroups(by);
    List<String> names = groups.keys.toList()
      ..sort((a, b) {
        bool unknownA = a == by.unknown, unknownB = b == by.unknown;
        if (unknownA != unknownB) return unknownA ? 1 : -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return [
      for (String name in names)
        _folder('$prefix$name', name, subtitle: _count(groups[name]!.length, "song"), art: _coverOf(groups[name]!)),
    ];
  }

  /// The songs in a song folder (not hidden, at most [maxQueue]); null if [folderId] isn't one.
  static Future<List<File>?> songsOf(String folderId, LibraryStore store) async {
    MusicLibrary library = MusicLibrary.instance;
    await library.load();
    bool visible(File song) => !store.isHidden(songKey(song));
    List<File> newestFirst() => library.songs.reversed.where(visible).toList();
    List<File> songs;
    if (folderId == songsId) {
      songs = newestFirst().where((s) => !store.isFilteredOut(songKey(s))).toList();
    } else if (folderId == favouritesId) {
      songs = newestFirst().where((s) => store.isFavourite(songKey(s))).toList();
    } else if (folderId.startsWith(smartPrefix)) {
      SmartPlaylist? smart = SmartPlaylist.values.asNameMap()[folderId.substring(smartPrefix.length)];
      if (smart == null) return null;
      songs = smart.pick<File>(newestFirst(), songKey, store);
    } else if (folderId.startsWith(playlistPrefix)) {
      Playlist? playlist = store.playlist(folderId.substring(playlistPrefix.length));
      if (playlist == null) return null;
      songs = playlist.songs.map(library.songNamed).whereType<File>().where(visible).toList();
    } else if (folderId.startsWith(albumPrefix)) {
      songs = browseGroups(BrowseBy.albums)[folderId.substring(albumPrefix.length)] ?? [];
    } else if (folderId.startsWith(artistPrefix)) {
      songs = browseGroups(BrowseBy.artists)[folderId.substring(artistPrefix.length)] ?? [];
    } else if (folderId.startsWith(genrePrefix)) {
      songs = browseGroups(BrowseBy.genres)[folderId.substring(genrePrefix.length)] ?? [];
    } else if (folderId.startsWith(searchPrefix)) {
      songs = _matchingSongs(folderId.substring(searchPrefix.length), newestFirst());
    } else {
      return null;
    }
    return songs.take(maxQueue).toList();
  }

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
      RadioStation? station = _stationFor(id, store);
      return station == null ? null : _station(station);
    } catch (e) {
      debugPrint("Error finding a car item: $e");
    }
    return null;
  }

  static RadioStation? _stationFor(String id, LibraryStore store) {
    if (!id.startsWith(stationPrefix)) return null;
    String url = id.substring(stationPrefix.length);
    return [...store.radioFavourites, ...store.radioRecent].where((s) => s.url == url).firstOrNull;
  }

  // ------------------------------------------------------------ Playing

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
      return;
    }
    RadioStation? station = _stationFor(id, store);
    if (station != null) {
      await player.playStream(station.url, station.name);
      store.addRadioRecent(station);
    }
  }

  static Future<bool> _playFolder(String folderId, LibraryStore store) async {
    List<File>? songs = await songsOf(folderId, store);
    if (songs == null || songs.isEmpty) return false;
    await PlayerService.instance.playQueue('car:$folderId', songs, 0);
    return true;
  }

  static List<File> _matchingSongs(String text, List<File> candidates) {
    String q = text.trim().toLowerCase();
    return candidates.where((song) {
      TrackInfo info = TrackInfoService.instance.infoFor(song);
      return [info.title, info.artist, info.album, info.genre].any((field) => field?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// The car's own search box: songs that match, as a list to play.
  static Future<List<MediaItem>> search(String query) async {
    try {
      LibraryStore store = await LibraryStore.instance();
      List<File> songs = await songsOf('$searchPrefix$query', store) ?? [];
      return [for (File song in songs.take(defaultPage)) _song('$searchPrefix$query', song)];
    } catch (e) {
      debugPrint("Error searching for the car: $e");
      return [];
    }
  }

  /// Voice ("play Sauti Sol", "play my favourites", "play the Road Trip playlist",
  /// "play Radio Maisha"): the first of these that matches wins: nothing said (any
  /// music), favourites, a playlist named exactly, an artist, album or genre named
  /// exactly, songs that match, a playlist whose name contains it, a station.
  static Future<void> playSearch(String query) async {
    String text = query.trim().toLowerCase();
    LibraryStore store = await LibraryStore.instance();
    MusicLibrary library = MusicLibrary.instance;
    await library.load();

    const anything = {'', 'music', 'some music', 'songs', 'my music', 'something', 'anything'};
    if (anything.contains(text)) {
      if (await _playFolder(recentlyPlayedId, store)) return;
      if (await _playFolder(songsId, store)) return;
    }
    if (text.contains('favourite') || text.contains('favorite')) {
      if (await _playFolder(favouritesId, store)) return;
    }
    List<Playlist> playlists = store.playlistsOf(MediaKind.audio);
    Playlist? exact = playlists.where((p) => p.name.toLowerCase() == text).firstOrNull;
    if (exact != null && await _playFolder('$playlistPrefix${exact.id}', store)) return;
    for ((BrowseBy, String) group in [
      (BrowseBy.artists, artistPrefix),
      (BrowseBy.albums, albumPrefix),
      (BrowseBy.genres, genrePrefix),
    ]) {
      String? name = browseGroups(group.$1).keys.where((n) => n.toLowerCase() == text).firstOrNull;
      if (name != null && await _playFolder('${group.$2}$name', store)) return;
    }
    if (await _playFolder('$searchPrefix$query', store)) return;
    Playlist? partial = playlists.where((p) => p.name.toLowerCase().contains(text)).firstOrNull;
    if (partial != null && await _playFolder('$playlistPrefix${partial.id}', store)) return;
    RadioStation? station = [...store.radioFavourites, ...store.radioRecent]
        .where((s) => s.name.toLowerCase().contains(text))
        .firstOrNull;
    if (station != null) {
      await PlayerService.instance.playStream(station.url, station.name);
      store.addRadioRecent(station);
    }
  }
}
