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
  final String? genre; // The first genre tag

  const TrackInfo({required this.title, this.artist, this.album, this.coverPath, this.duration, this.genre});

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

  /// Writes new tags into the song's file (the library's own copy, never the
  /// original) and re-reads them. A blank artist, album or genre removes that tag.
  /// False if the file couldn't be written.
  Future<bool> editTags(File file, {required String title, String? artist, String? album, String? genre}) async {
    bool written = await compute(_writeTags, (file.path, title, artist, album, genre));
    if (!written) return false;
    _cache.remove(file.path);
    await load([file]);
    return true;
  }

  /// Forgets a removed song and deletes its saved cover.
  Future<void> forget(File file) async {
    TrackInfo? info = _cache.remove(file.path);
    String? cover = info?.coverPath;
    if (cover != null && await File(cover).exists()) await File(cover).delete();
  }

  final Map<String, Future<String?>> _lyrics = {};

  /// The song's embedded lyrics (plain text, or LRC with its time stamps removed), or null.
  /// Read once, in a background isolate, then remembered.
  Future<String?> lyricsFor(File file) => _lyrics.putIfAbsent(file.path, () => compute(_readLyrics, file.path));

  Future<Directory> _covers() async {
    return _coverDir ??= await Directory('${(await getApplicationDocumentsDirectory()).path}/covers')
        .create(recursive: true);
  }
}

/// Runs in a background isolate: writes the tags of one file.
bool _writeTags((String, String, String?, String?, String?) job) {
  final (String path, String title, String? artist, String? album, String? genre) = job;
  try {
    updateMetadata(File(path), (tags) {
      tags.setTitle(title);
      tags.setArtist(artist);
      tags.setAlbum(album);
      tags.setGenres(genre == null ? [] : [genre]);
    });
    // Some files have no tag block to write into: check the change took.
    return readMetadata(File(path), getImage: false).title == title;
  } catch (_) {
    return false;
  }
}

/// Runs in a background isolate: the lyrics tag of one file.
String? _readLyrics(String path) {
  try {
    String? text = readMetadata(File(path), getImage: false).lyrics;
    return cleanLyrics(text);
  } catch (_) {
    return null;
  }
}

/// Lyrics ready to show: LRC time stamps like "[01:23.45]" removed (and its
/// "[ar:...]" header lines), blank ends trimmed. Null when nothing is left.
String? cleanLyrics(String? text) {
  if (text == null) return null;
  String cleaned = text
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'^\[[a-zA-Z]+:[^\]]*\]\s*$', multiLine: true), '')
      .replaceAll(RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
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
      genre: _firstGenre(tags),
    );
  } catch (_) {
    return TrackInfo(title: fallbackTitle, coverPath: existingCover);
  }
}

/// The song's first genre, or null. Old ID3v1 tags give a bare number or "(13)": skipped.
String? _firstGenre(AudioMetadata tags) {
  try {
    for (String genre in tags.genres) {
      String? clean = _clean(genre);
      if (clean != null && !RegExp(r'^\(?\d+\)?$').hasMatch(clean)) return clean;
    }
  } catch (_) {
    // genres is unset when the file has no genre tag
  }
  return null;
}

/// Trims a tag, treating blank text as missing.
String? _clean(String? text) {
  String? trimmed = text?.replaceAll('\u0000', '').trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
