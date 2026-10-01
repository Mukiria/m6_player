import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';

/// Asks for a playlist name. Null if cancelled or left blank.
Future<String?> askPlaylistName(BuildContext context, {String title = "New playlist", String initial = ""}) async {
  TextEditingController controller = TextEditingController(text: initial);
  String? name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: "Playlist name"),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text("Save")),
      ],
    ),
  );
  // Not disposed here: the dialog still uses it while it animates closed.
  name = name?.trim();
  return (name == null || name.isEmpty) ? null : name;
}

/// "Add to playlist" sheet: pick a playlist for [song], or make a new one.
Future<void> showAddToPlaylist(BuildContext context, File song) async {
  LibraryStore store = await LibraryStore.instance();
  if (!context.mounted) return;
  String? playlistId = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text("Add to playlist", style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: Icon(Icons.add),
            title: Text("New playlist"),
            onTap: () => Navigator.pop(context, ''),
          ),
          for (Playlist playlist in store.playlists)
            ListTile(
              leading: Icon(Icons.queue_music),
              title: Text(playlist.name),
              subtitle: Text("${playlist.songs.length} ${playlist.songs.length == 1 ? "song" : "songs"}"),
              onTap: () => Navigator.pop(context, playlist.id),
            ),
        ],
      ),
    ),
  );
  if (playlistId == null || !context.mounted) return;
  if (playlistId.isEmpty) {
    String? name = await askPlaylistName(context);
    if (name == null) return;
    playlistId = (await store.createPlaylist(name)).id;
  }
  bool added = await store.addToPlaylist(playlistId, songKey(song));
  if (!context.mounted) return;
  String name = store.playlist(playlistId)?.name ?? "the playlist";
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(added ? "Added to $name" : "Already in $name"),
  ));
}
