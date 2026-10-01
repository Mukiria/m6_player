import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'track_info.dart';

/// How the song list is ordered.
enum SortOrder {
  dateAdded('Date added'),
  title('Title'),
  artist('Artist');

  final String label;
  const SortOrder(this.label);
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

/// The user's favourites, Latest list, playlists, hidden and filtered-out
/// items and sort choice, saved as JSON in the app's folder.
///
/// Items are identified by a key: a song's file name in the library folder
/// ([songKey]) or "video:" plus the phone's id for a video ([videoKey]).
/// Screens listen to it and rebuild when something changes.
class LibraryStore extends ChangeNotifier {
  LibraryStore._(this._file);
  static LibraryStore? _instance;

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
  final Set<String> _favourites = {};
  final List<String> _latest = []; // Newest first
  final List<Playlist> _playlists = [];
  final Set<String> _hidden = {}; // Hidden from every list
  final Set<String> _filteredOut = {}; // Removed from the Songs or Videos list only

  SortOrder get sort => _sort;
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<Playlist> playlistsOf(MediaKind kind) => _playlists.where((p) => p.kind == kind).toList();
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
      Map<String, dynamic> json = jsonDecode(await _file.readAsString());
      _sort = SortOrder.values.asNameMap()[json['sort']] ?? SortOrder.dateAdded;
      _favourites.addAll((json['favourites'] as List? ?? []).cast<String>());
      _latest.addAll((json['latest'] as List? ?? []).cast<String>());
      _playlists.addAll((json['playlists'] as List? ?? []).map((p) => Playlist.fromJson(p)));
      _hidden.addAll((json['hidden'] as List? ?? []).cast<String>());
      _filteredOut.addAll((json['filteredOut'] as List? ?? []).cast<String>());
    } catch (e) {
      debugPrint("Error loading library.json: $e"); // Start fresh rather than crash
    }
  }

  Future<void> _changed() async {
    notifyListeners();
    try {
      await _file.writeAsString(jsonEncode({
        'sort': _sort.name,
        'favourites': _favourites.toList(),
        'latest': _latest,
        'playlists': _playlists.map((p) => p.toJson()).toList(),
        'hidden': _hidden.toList(),
        'filteredOut': _filteredOut.toList(),
      }));
    } catch (e) {
      debugPrint("Error saving library.json: $e");
    }
  }

  Future<void> setSort(SortOrder sort) async {
    _sort = sort;
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

  /// An item was deleted: drop it from favourites, Latest, playlists, hidden and filtered.
  Future<void> forgetSong(String key) async {
    _favourites.remove(key);
    _latest.remove(key);
    _hidden.remove(key);
    _filteredOut.remove(key);
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
