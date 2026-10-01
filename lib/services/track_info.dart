import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'player_service.dart';

/// What the app shows for a song: its title, artist and album from the MP3's
/// tags, and its cover art saved as an image file (so the lock screen and
/// notification can show it too). Missing tags fall back to the file name.
class TrackInfo {
  final String title;
  final String? artist;
  final String? album;
  final String? coverPath;
  final Duration? duration; // From the file's audio frames, when readable

  const TrackInfo({required this.title, this.artist, this.album, this.coverPath, this.duration});

  /// Artist (and album when known) for the line under the title.
  String get subtitle => songSubtitle(artist, album);
}

/// Reads and remembers song tags. Tags are read in a background isolate, so a
/// big library doesn't freeze the screen, and covers are written to disk once.
class TrackInfoService {
  TrackInfoService._();
  static final TrackInfoService instance = TrackInfoService._();

  final Map<String, TrackInfo> _cache = {};
  Directory? _coverDir;

  /// The info for [file] if it has been read, otherwise one built from the file name.
  TrackInfo infoFor(File file) => _cache[file.path] ?? TrackInfo(title: trackTitle(file));

  /// Reads the tags of every song in [files] that hasn't been read yet.
  Future<void> load(List<File> files) async {
    List<String> paths = files.map((file) => file.path).where((path) => !_cache.containsKey(path)).toList();
    if (paths.isEmpty) return;
    String coverDir = (await _covers()).path;
    List<TrackInfo> infos = await compute(_readAll, (paths, coverDir));
    for (int i = 0; i < paths.length; i++) {
      _cache[paths[i]] = infos[i];
    }
  }

  /// Forgets a removed song and deletes its saved cover.
  Future<void> forget(File file) async {
    TrackInfo? info = _cache.remove(file.path);
    String? cover = info?.coverPath;
    if (cover != null && await File(cover).exists()) await File(cover).delete();
  }

  Future<Directory> _covers() async {
    return _coverDir ??= await Directory('${(await getApplicationDocumentsDirectory()).path}/covers')
        .create(recursive: true);
  }
}

/// Runs in a background isolate: reads the tags of every path.
List<TrackInfo> _readAll((List<String>, String) job) {
  final (List<String> paths, String coverDir) = job;
  return paths.map((path) => readTrackInfo(File(path), coverDir)).toList();
}

/// Reads [file]'s tags, saving its cover into [coverDir] (named after the song
/// file) unless it's already there. Never throws: a file that can't be read
/// gets its file name as the title.
TrackInfo readTrackInfo(File file, String coverDir) {
  String fallbackTitle = trackTitle(file);
  String coverBase = '$coverDir/${file.uri.pathSegments.last}';
  String? existingCover = ['.jpg', '.png']
      .map((ext) => '$coverBase$ext')
      .where((path) => File(path).existsSync())
      .firstOrNull;
  try {
    // Covers can be several MB, so only extract one when it isn't saved yet.
    AudioMetadata tags = readMetadata(file, getImage: existingCover == null);
    String? coverPath = existingCover;
    if (coverPath == null && tags.pictures.isNotEmpty) {
      // Prefer the front cover when the file has several pictures.
      Picture picture = tags.pictures.firstWhere(
        (p) => p.pictureType == PictureType.coverFront,
        orElse: () => tags.pictures.first,
      );
      coverPath = '$coverBase${picture.mimetype.contains('png') ? '.png' : '.jpg'}';
      File(coverPath).writeAsBytesSync(picture.bytes);
    }
    return TrackInfo(
      title: _clean(tags.title) ?? fallbackTitle,
      artist: _clean(tags.artist) ?? _clean(tags.albumArtist),
      album: _clean(tags.album),
      coverPath: coverPath,
      duration: tags.duration,
    );
  } catch (_) {
    return TrackInfo(title: fallbackTitle, coverPath: existingCover);
  }
}

/// Trims a tag, treating blank text as missing.
String? _clean(String? text) {
  String? trimmed = text?.replaceAll('\u0000', '').trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
