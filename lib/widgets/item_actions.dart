import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import '../screens/transfer_screen.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../services/track_info.dart';
import '../services/video_library.dart';
import '../utils/format.dart';
import 'artwork.dart';
import 'options_sheet.dart';
import 'playlist_picker.dart';

/// Which list an item's ⋮ menu was opened from; decides what "Filter out" does.
enum ItemList {
  all, // Songs or Videos: hidden from that list only
  favourites, // Taken out of Favourites
  latest, // Taken out of Latest
  playlist, // Taken out of this playlist
}

/// The ⋮ menu for a song.
Future<void> showSongOptions(BuildContext context, File song, {ItemList from = ItemList.all, String? playlistId}) async {
  LibraryStore store = await LibraryStore.instance();
  if (!context.mounted) return;
  TrackInfo info = TrackInfoService.instance.infoFor(song);
  String key = songKey(song);
  PlayerService player = PlayerService.instance;

  await showOptionsSheet(
    context,
    title: info.title,
    subtitle: info.subtitle,
    leading: Artwork(size: 44, coverPath: info.coverPath),
    options: _commonOptions(
      context,
      store: store,
      key: key,
      kind: MediaKind.audio,
      title: info.title,
      from: from,
      playlistId: playlistId,
      playNext: () async {
        await player.playNext(song);
        _message(context, "Plays next");
      },
      playLast: () async {
        await player.playLast(song);
        _message(context, "Added to the end of the queue");
      },
      file: () async => song,
      info: () => showInfoSheet(context, title: info.title, rows: {
        "Title": info.title,
        "Artist": info.artist ?? "",
        "Album": info.album ?? "",
        "Length": info.duration == null ? "" : formatDuration(info.duration!),
        "Size": _size(song),
        "Format": _extension(song),
        "File name": songKey(song),
        "Added": _date(song.lastModifiedSync()),
      }),
      edit: () => _editSong(context, song, info),
      delete: () => _deleteSong(context, song, info.title),
    ),
  );
}

/// The ⋮ menu for a video.
Future<void> showVideoOptions(BuildContext context, AssetEntity video, String title,
    {ItemList from = ItemList.all, String? playlistId}) async {
  LibraryStore store = await LibraryStore.instance();
  if (!context.mounted) return;
  VideoLibrary videos = VideoLibrary.instance;
  String resolution = video.height > 0 ? "${video.width} × ${video.height}" : "";

  await showOptionsSheet(
    context,
    title: title,
    subtitle: [formatDuration(video.videoDuration), resolution].where((s) => s.isNotEmpty).join(" · "),
    options: _commonOptions(
      context,
      store: store,
      key: videoKey(video.id),
      kind: MediaKind.video,
      title: title,
      from: from,
      playlistId: playlistId,
      playNext: () {
        videos.playNext(video);
        _message(context, "Plays next (up next: ${videos.upNext.length})");
      },
      playLast: () {
        videos.playLast(video);
        _message(context, "Added to up next (${videos.upNext.length})");
      },
      file: () => video.file,
      info: () async {
        File? file = await video.file;
        if (!context.mounted) return;
        await showInfoSheet(context, title: title, rows: {
          "Name": video.title ?? title,
          "Length": formatDuration(video.videoDuration),
          "Resolution": resolution,
          "Size": file == null ? "" : _size(file),
          "Date": _date(video.createDateTime),
          "Folder": video.relativePath ?? "",
        });
      },
      delete: () async {
        // Android shows its own "Allow m6 player to delete this video?" prompt.
        bool deleted = await videos.delete(video);
        if (context.mounted && !deleted) _message(context, "The video wasn't deleted");
      },
    ),
  );
}

/// The buttons both menus share, in the order asked for.
List<SheetOption> _commonOptions(
  BuildContext context, {
  required LibraryStore store,
  required String key,
  required MediaKind kind,
  required String title,
  required ItemList from,
  required String? playlistId,
  required VoidCallback playNext,
  required VoidCallback playLast,
  required Future<File?> Function() file,
  required VoidCallback info,
  VoidCallback? edit, // Songs only
  required VoidCallback delete,
}) {
  bool isFavourite = store.isFavourite(key);
  return [
    SheetOption(icon: Icons.playlist_play, label: "Play next", onTap: playNext),
    SheetOption(icon: Icons.queue_music, label: "Play last", onTap: playLast),
    // Nearby transfer uses Google's Nearby Connections, which is Android-only.
    if (Platform.isAndroid)
      SheetOption(
        icon: Icons.swap_horiz,
        label: "File transfer",
        onTap: () async {
          File? source = await file();
          if (!context.mounted) return;
          if (source == null) {
            _message(context, "This file isn't available");
            return;
          }
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => TransferScreen(sendPath: source.path, sendName: _fileName(source, title), kind: kind),
          ));
        },
      ),
    SheetOption(
      icon: isFavourite ? Icons.favorite : Icons.favorite_border,
      label: isFavourite ? "Remove from favourites" : "Favourite",
      onTap: () => store.toggleFavourite(key),
    ),
    SheetOption(
      icon: Icons.share_outlined,
      label: "Share",
      onTap: () async {
        File? source = await file();
        if (source == null) {
          if (context.mounted) _message(context, "This file isn't available");
          return;
        }
        await SharePlus.instance.share(ShareParams(files: [XFile(source.path)], title: title));
      },
    ),
    SheetOption(
      icon: Icons.library_add_outlined,
      label: "Add to…",
      onTap: () => showAddTo(context, key: key, kind: kind),
    ),
    SheetOption(
      icon: Icons.visibility_off_outlined,
      label: "Hide",
      onTap: () async {
        await store.hide(key);
        if (context.mounted) _message(context, "Hidden. Find it again under Hidden.", undo: () => store.unhide(key));
      },
    ),
    SheetOption(
      icon: Icons.filter_alt_off_outlined,
      label: "Filter out",
      onTap: () => _filterOut(context, store, key, from, playlistId),
    ),
    if (edit != null) SheetOption(icon: Icons.edit_outlined, label: "Edit info", onTap: edit),
    SheetOption(icon: Icons.info_outline, label: "Info", onTap: info),
    SheetOption(icon: Icons.delete_outline, label: "Delete", destructive: true, onTap: delete),
  ];
}

/// Takes the item out of the list the menu was opened from; nothing is deleted.
Future<void> _filterOut(BuildContext context, LibraryStore store, String key, ItemList from, String? playlistId) async {
  switch (from) {
    case ItemList.all:
      await store.filterOut(key);
      if (context.mounted) {
        _message(context, "Filtered out of this list. Restore it under Hidden.",
            undo: () => store.restoreFilteredOut(key));
      }
    case ItemList.favourites:
      await store.toggleFavourite(key);
      if (context.mounted) _message(context, "Removed from Favourites", undo: () => store.toggleFavourite(key));
    case ItemList.latest:
      await store.removeFromLatest(key);
      if (context.mounted) _message(context, "Removed from Latest", undo: () => store.addToLatest(key));
    case ItemList.playlist:
      if (playlistId == null) return;
      await store.removeFromPlaylist(playlistId, key);
      if (context.mounted) {
        _message(context, "Removed from the playlist", undo: () => store.addToPlaylist(playlistId, key));
      }
  }
}

/// Edit a song's title, artist, album and genre. Written into the library's copy of the file.
Future<void> _editSong(BuildContext context, File song, TrackInfo info) async {
  TextEditingController title = TextEditingController(text: info.title);
  TextEditingController artist = TextEditingController(text: info.artist ?? '');
  TextEditingController album = TextEditingController(text: info.album ?? '');
  TextEditingController genre = TextEditingController(text: info.genre ?? '');
  bool save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Edit info"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for ((String, TextEditingController) field in [
                  ("Title", title),
                  ("Artist", artist),
                  ("Album", album),
                  ("Genre", genre),
                ])
                  TextField(
                    controller: field.$2,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: field.$1),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Save")),
          ],
        ),
      ) ??
      false;
  String newTitle = title.text.trim();
  if (!save || newTitle.isEmpty) return;
  String? clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  bool done = await TrackInfoService.instance
      .editTags(song, title: newTitle, artist: clean(artist), album: clean(album), genre: clean(genre));
  if (done) MusicLibrary.instance.tagsChanged();
  _message(
      context,
      done
          ? "Saved. The player shows the new info the next time the song starts."
          : "Couldn't save the changes to this file");
}

Future<void> _deleteSong(BuildContext context, File song, String title) async {
  bool confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Delete song?"),
          content: Text("Delete \"$title\" from M6 Player? It's also removed from your favourites and playlists. "
              "The original file on your device is not affected."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Delete")),
          ],
        ),
      ) ??
      false;
  if (confirmed) await MusicLibrary.instance.delete(song);
}

void _message(BuildContext context, String text, {VoidCallback? undo}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    action: undo == null ? null : SnackBarAction(label: "Undo", onPressed: undo),
  ));
}

/// The name to send a file under: its own name, or the title plus its extension.
String _fileName(File file, String title) {
  String name = file.uri.pathSegments.last;
  return name.contains('.') ? name : '$title.${_extension(file).toLowerCase()}';
}

String _extension(File file) {
  String name = file.uri.pathSegments.last;
  int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toUpperCase() : "";
}

String _size(File file) {
  try {
    double mb = file.lengthSync() / (1024 * 1024);
    return mb >= 1 ? "${mb.toStringAsFixed(1)} MB" : "${(mb * 1024).toStringAsFixed(0)} KB";
  } catch (_) {
    return "";
  }
}

String _date(DateTime date) =>
    "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
