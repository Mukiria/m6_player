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

/// A named list of songs, in the order the user added them.
class Playlist {
  final String id; // Stays the same when the playlist is renamed
  String name;
  final List<String> songs; // Song file names in the library folder

  Playlist({required this.id, required this.name, List<String>? songs}) : songs = songs ?? [];

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'songs': songs};

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        songs: (json['songs'] as List).cast<String>(),
      );
}

/// The user's favourites, playlists and sort choice, saved as JSON in the app's
/// folder. Songs are identified by their file name in the library folder, which
/// is unique. Screens listen to it and rebuild when something changes.
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
  final List<Playlist> _playlists = [];

  SortOrder get sort => _sort;
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool isFavourite(String song) => _favourites.contains(song);

  Playlist? playlist(String id) => _playlists.where((p) => p.id == id).firstOrNull;

  Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      Map<String, dynamic> json = jsonDecode(await _file.readAsString());
      _sort = SortOrder.values.asNameMap()[json['sort']] ?? SortOrder.dateAdded;
      _favourites.addAll((json['favourites'] as List? ?? []).cast<String>());
      _playlists.addAll((json['playlists'] as List? ?? []).map((p) => Playlist.fromJson(p)));
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
        'playlists': _playlists.map((p) => p.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint("Error saving library.json: $e");
    }
  }

  Future<void> setSort(SortOrder sort) async {
    _sort = sort;
    await _changed();
  }

  Future<void> toggleFavourite(String song) async {
    if (!_favourites.remove(song)) _favourites.add(song);
    await _changed();
  }

  Future<Playlist> createPlaylist(String name) async {
    Playlist playlist = Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim());
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

  /// Adds [song] to the end of a playlist. Returns false if it was already there.
  Future<bool> addToPlaylist(String id, String song) async {
    Playlist? list = playlist(id);
    if (list == null || list.songs.contains(song)) return false;
    list.songs.add(song);
    await _changed();
    return true;
  }

  Future<void> removeFromPlaylist(String id, String song) async {
    playlist(id)?.songs.remove(song);
    await _changed();
  }

  /// A song was deleted from the library: drop it from favourites and playlists.
  Future<void> forgetSong(String song) async {
    _favourites.remove(song);
    for (Playlist list in _playlists) {
      list.songs.remove(song);
    }
    await _changed();
  }
}

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
