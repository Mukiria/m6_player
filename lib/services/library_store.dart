import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'radio_api.dart';
import 'track_info.dart';

/// How the song list is ordered.
enum SortOrder {
  dateAdded('Date added'),
  title('Title'),
  artist('Artist');

  final String label;
  const SortOrder(this.label);
}

/// How the Videos and Favourites lists on the Video tab are ordered.
enum VideoSort {
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name'),
  longest('Longest first');

  final String label;
  const VideoSort(this.label);
}

/// Whether a list holds songs or videos.
enum MediaKind { audio, video }

/// A named list of songs or videos, in the order the user added them.
class Playlist {
  final String id; // Stays the same when the playlist is renamed
  String name;
  final MediaKind kind;
  final List<String> songs; // Item keys: songKey() for songs, videoKey() for videos

  Playlist({required this.id, required this.name, this.kind = MediaKind.audio, List<String>? songs})
      : songs = songs ?? [];

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name, 'songs': songs};

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: MediaKind.values.asNameMap()[json['kind']] ?? MediaKind.audio,
        songs: (json['songs'] as List).cast<String>(),
      );
}

/// Marks a backup file as made by this app.
const String backupMarker = 'm6player-backup';

/// The user's favourites, Latest list, playlists, hidden and filtered-out
/// items and sort choice, saved as JSON in the app's folder.
///
/// Items are identified by a key: a song's file name in the library folder
/// ([songKey]) or "video:" plus the phone's id for a video ([videoKey]).
/// Screens listen to it and rebuild when something changes.
class LibraryStore extends ChangeNotifier {
  LibraryStore._(this._file);
  static LibraryStore? _instance;

  /// The store if it has been opened already (null before first use).
  static LibraryStore? get loaded => _instance;

  /// The app-wide store, loaded from disk on first use.
  static Future<LibraryStore> instance() async {
    if (_instance == null) {
      Directory docs = await getApplicationDocumentsDirectory();
      _instance = await LibraryStore.open(File('${docs.path}/library.json'));
    }
    return _instance!;
  }

  /// A store saved in [file] (tests use a temporary file).
  static Future<LibraryStore> open(File file) async {
    LibraryStore store = LibraryStore._(file);
    await store._load();
    return store;
  }

  final File _file;
  SortOrder _sort = SortOrder.dateAdded;
  VideoSort _videoSort = VideoSort.newest;
  final Set<String> _favourites = {};
  final List<String> _latest = []; // Newest first
  final List<Playlist> _playlists = [];
  final Set<String> _hidden = {}; // Hidden from every list
  final Set<String> _filteredOut = {}; // Removed from the Songs or Videos list only
  final List<RadioStation> _radioFavourites = []; // Newest first
  final List<RadioStation> _radioRecent = []; // Last played first
  final Map<String, (int, int)> _plays = {}; // Item key: (times played, last played in ms since epoch)
  final Map<String, int> _positions = {}; // Where each video stopped, in milliseconds

  SortOrder get sort => _sort;
  VideoSort get videoSort => _videoSort;
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<Playlist> playlistsOf(MediaKind kind) => _playlists.where((p) => p.kind == kind).toList();
  List<RadioStation> get radioRecent => List.unmodifiable(_radioRecent);
  List<RadioStation> get radioFavourites => List.unmodifiable(_radioFavourites);
  bool isRadioFavourite(String url) => _radioFavourites.any((s) => s.url == url);
  bool isFavourite(String key) => _favourites.contains(key);
  bool isLatest(String key) => _latest.contains(key);
  bool isHidden(String key) => _hidden.contains(key);
  bool isFilteredOut(String key) => _filteredOut.contains(key);

  /// The Latest list, newest first.
  List<String> get latest => List.unmodifiable(_latest);
  Set<String> get hidden => Set.unmodifiable(_hidden);
  Set<String> get filteredOut => Set.unmodifiable(_filteredOut);

  Playlist? playlist(String id) => _playlists.where((p) => p.id == id).firstOrNull;

  Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      _apply(jsonDecode(await _file.readAsString()));
    } catch (e) {
      debugPrint("Error loading library.json: $e"); // Start fresh rather than crash
    }
  }

  /// Replaces everything with what's in [json] (the saved file, or a backup).
  void _apply(Map<String, dynamic> json) {
    _sort = SortOrder.values.asNameMap()[json['sort']] ?? SortOrder.dateAdded;
    _videoSort = VideoSort.values.asNameMap()[json['videoSort']] ?? VideoSort.newest;
    _favourites
      ..clear()
      ..addAll((json['favourites'] as List? ?? []).cast<String>());
    _latest
      ..clear()
      ..addAll((json['latest'] as List? ?? []).cast<String>());
    _playlists
      ..clear()
      ..addAll((json['playlists'] as List? ?? []).map((p) => Playlist.fromJson(p)));
    _hidden
      ..clear()
      ..addAll((json['hidden'] as List? ?? []).cast<String>());
    _filteredOut
      ..clear()
      ..addAll((json['filteredOut'] as List? ?? []).cast<String>());
    _radioFavourites
      ..clear()
      ..addAll((json['radioFavourites'] as List? ?? []).map((s) =>
          RadioStation(name: s['name'] as String, url: s['url'] as String, country: s['country'] as String? ?? '')));
    _radioRecent
      ..clear()
      ..addAll((json['radioRecent'] as List? ?? []).map((s) =>
          RadioStation(name: s['name'] as String, url: s['url'] as String, country: s['country'] as String? ?? '')));
    _plays.clear();
    (json['plays'] as Map? ?? {}).forEach((key, value) {
      List list = value as List;
      _plays[key as String] = ((list[0] as num).toInt(), (list[1] as num).toInt());
    });
    _positions.clear();
    (json['positions'] as Map? ?? {}).forEach((key, ms) => _positions[key as String] = (ms as num).toInt());
  }

  Map<String, dynamic> toJson() => {
        'sort': _sort.name,
        'videoSort': _videoSort.name,
        'favourites': _favourites.toList(),
        'latest': _latest,
        'playlists': _playlists.map((p) => p.toJson()).toList(),
        'hidden': _hidden.toList(),
        'filteredOut': _filteredOut.toList(),
        'radioFavourites': _radioFavourites.map((s) => {'name': s.name, 'url': s.url, 'country': s.country}).toList(),
        'radioRecent': _radioRecent.map((s) => {'name': s.name, 'url': s.url, 'country': s.country}).toList(),
        'plays': {for (MapEntry<String, (int, int)> e in _plays.entries) e.key: [e.value.$1, e.value.$2]},
        'positions': _positions,
      };

  /// Replaces the whole library with a backup made by [toJson]. Throws if it isn't one.
  Future<void> restoreFrom(String backup) async {
    Object? json = jsonDecode(backup);
    if (json is! Map<String, dynamic> || json['app'] != backupMarker) throw FormatException("Not an M6 Player backup");
    _apply(json);
    await _changed();
  }

  Future<void> _changed() async {
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      await _file.writeAsString(jsonEncode(toJson()));
    } catch (e) {
      debugPrint("Error saving library.json: $e");
    }
  }

  /// The backup file's text: the library plus a marker so a restore can tell it's ours.
  String backupJson() => jsonEncode({'app': backupMarker, ...toJson()});

  /// Adds every key to Favourites. Returns how many were new.
  Future<int> addAllToFavourites(Iterable<String> keys) async {
    int before = _favourites.length;
    _favourites.addAll(keys);
    await _changed();
    return _favourites.length - before;
  }

  Future<void> addAllToLatest(Iterable<String> keys) async {
    for (String key in keys.toList().reversed) {
      _latest.remove(key);
      _latest.insert(0, key);
    }
    await _changed();
  }

  /// Adds every key to a playlist. Returns how many were new.
  Future<int> addAllToPlaylist(String id, Iterable<String> keys) async {
    Playlist? list = playlist(id);
    if (list == null) return 0;
    int added = 0;
    for (String key in keys) {
      if (!list.songs.contains(key)) {
        list.songs.add(key);
        added++;
      }
    }
    await _changed();
    return added;
  }

  Future<void> hideAll(Iterable<String> keys) async {
    _hidden.addAll(keys);
    await _changed();
  }

  Future<void> filterOutAll(Iterable<String> keys) async {
    _filteredOut.addAll(keys);
    await _changed();
  }

  Future<void> setSort(SortOrder sort) async {
    _sort = sort;
    await _changed();
  }

  Future<void> setVideoSort(VideoSort sort) async {
    _videoSort = sort;
    await _changed();
  }

  /// Puts a station at the top of the recently played list (at most 30 are kept).
  Future<void> addRadioRecent(RadioStation station) async {
    _radioRecent.removeWhere((s) => s.url == station.url);
    _radioRecent.insert(0, station);
    if (_radioRecent.length > 30) _radioRecent.removeRange(30, _radioRecent.length);
    await _changed();
  }

  Future<void> clearRadioRecent() async {
    _radioRecent.clear();
    await _changed();
  }

  Future<void> toggleRadioFavourite(RadioStation station) async {
    int at = _radioFavourites.indexWhere((s) => s.url == station.url);
    if (at >= 0) {
      _radioFavourites.removeAt(at);
    } else {
      _radioFavourites.insert(0, station);
    }
    await _changed();
  }

  Future<void> toggleFavourite(String key) async {
    if (!_favourites.remove(key)) _favourites.add(key);
    await _changed();
  }

  /// Adds to the top of Latest (moving it there if it's already in the list).
  Future<void> addToLatest(String key) async {
    _latest.remove(key);
    _latest.insert(0, key);
    await _changed();
  }

  Future<void> removeFromLatest(String key) async {
    _latest.remove(key);
    await _changed();
  }

  Future<void> hide(String key) async {
    _hidden.add(key);
    await _changed();
  }

  Future<void> unhide(String key) async {
    _hidden.remove(key);
    await _changed();
  }

  /// Removes an item from the Songs or Videos list only (it stays in other lists).
  Future<void> filterOut(String key) async {
    _filteredOut.add(key);
    await _changed();
  }

  Future<void> restoreFilteredOut(String key) async {
    _filteredOut.remove(key);
    await _changed();
  }

  Future<Playlist> createPlaylist(String name, {MediaKind kind = MediaKind.audio}) async {
    Playlist playlist =
        Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim(), kind: kind);
    _playlists.add(playlist);
    await _changed();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    playlist(id)?.name = name.trim();
    await _changed();
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    await _changed();
  }

  /// Adds an item to the end of a playlist. Returns false if it was already there.
  Future<bool> addToPlaylist(String id, String key) async {
    Playlist? list = playlist(id);
    if (list == null || list.songs.contains(key)) return false;
    list.songs.add(key);
    await _changed();
    return true;
  }

  Future<void> removeFromPlaylist(String id, String key) async {
    playlist(id)?.songs.remove(key);
    await _changed();
  }

  int playCount(String key) => _plays[key]?.$1 ?? 0;

  /// When the item was last played, or null if never.
  DateTime? lastPlayed(String key) {
    int? ms = _plays[key]?.$2;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Counts a play of a song or video. Saves quietly: lists don't re-sort under you while you listen.
  Future<void> recordPlay(String key) async {
    _plays[key] = (playCount(key) + 1, DateTime.now().millisecondsSinceEpoch);
    await _save();
  }

  /// Where a video stopped last time, or null to start from the beginning.
  Duration? positionOf(String key) => _positions.containsKey(key) ? Duration(milliseconds: _positions[key]!) : null;

  /// Remembers where a video stopped (null forgets it). Saves quietly: nothing listens to positions.
  Future<void> setPosition(String key, Duration? position) async {
    if (position == null) {
      if (_positions.remove(key) == null) return;
    } else {
      _positions[key] = position.inMilliseconds;
    }
    await _save();
  }

  /// An item was deleted: drop it from favourites, Latest, playlists, hidden and filtered.
  Future<void> forgetSong(String key) async {
    _favourites.remove(key);
    _latest.remove(key);
    _hidden.remove(key);
    _filteredOut.remove(key);
    _positions.remove(key);
    _plays.remove(key);
    for (Playlist list in _playlists) {
      list.songs.remove(key);
    }
    await _changed();
  }
}

/// Key of a video on the phone, as stored in favourites and lists.
String videoKey(String assetId) => 'video:$assetId';

/// The phone's id of a video key, or null for a song key.
String? videoIdOf(String key) => key.startsWith('video:') ? key.substring(6) : null;

/// File name of a library song, which is how the store identifies it.
String songKey(File file) => file.uri.pathSegments.last;

/// [songs] (oldest first, as loaded from the library) in the chosen order.
/// Title and artist sorts ignore case; songs with no artist go last.
List<File> sortSongs(List<File> songs, SortOrder order, TrackInfo Function(File) info) {
  List<File> sorted = List.of(songs);
  int byTitle(File a, File b) => info(a).title.toLowerCase().compareTo(info(b).title.toLowerCase());
  switch (order) {
    case SortOrder.dateAdded:
      break;
    case SortOrder.title:
      sorted.sort(byTitle);
    case SortOrder.artist:
      sorted.sort((a, b) {
        String? artistA = info(a).artist?.toLowerCase(), artistB = info(b).artist?.toLowerCase();
        if (artistA != artistB) {
          if (artistA == null) return 1;
          if (artistB == null) return -1;
          return artistA.compareTo(artistB);
        }
        return byTitle(a, b);
      });
  }
  return sorted;
}
