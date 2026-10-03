import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/track_info.dart';
import '../utils/file_helper.dart';
import 'artwork.dart';

/// A playlist's picture: the one the user chose, otherwise a cover for its songs.
class PlaylistCover extends StatelessWidget {
  final Playlist playlist;
  final double size;

  const PlaylistCover({super.key, required this.playlist, required this.size});

  @override
  Widget build(BuildContext context) {
    String? own = playlist.coverPath;
    if (own != null) return Artwork(size: size, coverPath: own);
    return ListCover(keys: playlist.songs, size: size);
  }
}

/// A cover made from songs' covers: a 2x2 collage of four, one cover filling
/// the square for fewer, otherwise the brand placeholder with [icon].
class ListCover extends StatelessWidget {
  final List<String> keys; // Song keys (see songKey)
  final double size;
  final String? m6Icon; // An M6Icon name for the placeholder
  final bool whitePlaceholder;

  const ListCover({super.key, required this.keys, required this.size, this.m6Icon, this.whitePlaceholder = false});

  List<String> get _covers => keys
      .map(MusicLibrary.instance.songNamed)
      .whereType<File>()
      .map((song) => TrackInfoService.instance.infoFor(song).coverPath)
      .whereType<String>()
      .toSet() // The songs of one album share a cover
      .take(4)
      .toList();

  @override
  Widget build(BuildContext context) {
    List<String> covers = _covers;
    if (covers.length < 4) return Artwork(size: size, coverPath: covers.firstOrNull, m6Icon: m6Icon, whitePlaceholder: whitePlaceholder);
    double half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.08),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(
          children: [
            for (String cover in covers)
              SizedBox(
                width: half,
                height: half,
                child: Image.file(
                  File(cover),
                  fit: BoxFit.cover,
                  cacheWidth: (half * MediaQuery.devicePixelRatioOf(context)).round(),
                  errorBuilder: (context, error, stack) =>
                      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks the user for a picture and makes it the playlist's cover.
Future<void> chooseCoverPhoto(BuildContext context, Playlist playlist) async {
  ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    File? picked = await pickImage();
    if (picked == null) return;
    String saved = await saveCoverImage(picked);
    await (await LibraryStore.instance()).setPlaylistCover(playlist.id, saved);
  } catch (e) {
    debugPrint("Error choosing a cover photo: $e");
    messenger.showSnackBar(SnackBar(content: Text("Couldn't use that picture.")));
  }
}

Future<void> removeCoverPhoto(Playlist playlist) async =>
    (await LibraryStore.instance()).setPlaylistCover(playlist.id, null);
