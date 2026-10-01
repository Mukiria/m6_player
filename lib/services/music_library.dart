import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../utils/file_helper.dart';
import 'library_store.dart';
import 'player_service.dart';
import 'track_info.dart';

/// The songs in m6 player's library folder, shared by the Music tab, playlist
/// pages and Now Playing. Adding and deleting songs goes through here so the
/// player, tags, favourites and playlists stay in step.
class MusicLibrary extends ChangeNotifier {
  MusicLibrary._();
  static final MusicLibrary instance = MusicLibrary._();

  final PlayerService _player = PlayerService.instance;
  final TrackInfoService _tracks = TrackInfoService.instance;

  Directory? _dir;
  List<File> _songs = []; // Oldest first, in the order they were added
  bool isLoaded = false;

  List<File> get songs => List.unmodifiable(_songs);

  /// The library song with this file name, if it's still there.
  File? songNamed(String name) => _songs.where((file) => songKey(file) == name).firstOrNull;

  /// Loads the library folder, then reads the songs' tags (titles, artists, covers).
  Future<void> load() async {
    if (isLoaded) return;
    try {
      _dir = await libraryDirectory();
      _songs = await loadLibrary(_dir!);
      isLoaded = true;
      notifyListeners();
      await _tracks.load(_songs);
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading library: $e");
    }
  }

  /// Copies [picked] songs into the library, skipping ones already there.
  /// Returns how many were added and how many skipped.
  Future<(int, int)> importSongs(List<File> picked) async {
    if (_dir == null) return (0, 0);
    int added = 0, skipped = 0;
    for (File source in picked) {
      try {
        if (isInLibrary(source, _songs)) {
          skipped++;
          continue;
        }
        File file = await importToLibrary(source, _dir!);
        _songs.add(file);
        await _player.addTrack(file); // Joins the end of "all songs" if that's playing
        added++;
        notifyListeners();
      } catch (e) {
        debugPrint("Error adding ${source.path}: $e");
      }
    }
    await _tracks.load(_songs); // Tags for the new songs (already-read ones are skipped)
    notifyListeners();
    return (added, skipped);
  }

  /// Deletes the app's copy of [file], and takes it out of the player,
  /// favourites and playlists.
  Future<void> delete(File file) async {
    await _player.removeTrack(file);
    await removeFromLibrary(file);
    await _tracks.forget(file);
    await (await LibraryStore.instance()).forgetSong(songKey(file));
    PaintingBinding.instance.imageCache.clear(); // Drop its cover, in case a new song reuses the name
    _songs.removeWhere((song) => song.path == file.path); // File has no value equality
    notifyListeners();
  }
}
