import 'package:flutter/material.dart';
import '../services/library_store.dart';
import 'options_sheet.dart';

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

/// "Add to" sheet: Favourites, Latest, one of the playlists for this kind of
/// item, or a new playlist. [key] is the item's songKey() or videoKey().
Future<void> showAddTo(BuildContext context, {required String key, required MediaKind kind}) =>
    showAddToMany(context, keys: [key], kind: kind);

/// [showAddTo] for several items at once (multi-select).
Future<void> showAddToMany(BuildContext context, {required List<String> keys, required MediaKind kind}) async {
  if (keys.length == 1) return _showAddToOne(context, key: keys.first, kind: kind);
  LibraryStore store = await LibraryStore.instance();
  if (!context.mounted) return;
  ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  void done(String message) => messenger.showSnackBar(SnackBar(content: Text(message)));
  String count = "${keys.length} items";

  await showOptionsSheet(
    context,
    title: "Add $count to",
    options: [
      SheetOption(
        icon: Icons.favorite_border,
        label: "Favourites",
        onTap: () async {
          await store.addAllToFavourites(keys);
          done("Added $count to Favourites");
        },
      ),
      SheetOption(
        icon: Icons.fiber_new_outlined,
        label: "Latest",
        onTap: () async {
          await store.addAllToLatest(keys);
          done("Added $count to Latest");
        },
      ),
      for (Playlist playlist in store.playlistsOf(kind))
        SheetOption(
          icon: Icons.queue_music,
          label: playlist.name,
          onTap: () async {
            int added = await store.addAllToPlaylist(playlist.id, keys);
            done("Added $added to ${playlist.name}");
          },
        ),
      SheetOption(
        icon: Icons.playlist_add,
        label: "New playlist…",
        onTap: () async {
          if (!context.mounted) return;
          String? name = await askPlaylistName(context);
          if (name == null) return;
          Playlist playlist = await store.createPlaylist(name, kind: kind);
          await store.addAllToPlaylist(playlist.id, keys);
          done("Added $count to ${playlist.name}");
        },
      ),
    ],
  );
}

Future<void> _showAddToOne(BuildContext context, {required String key, required MediaKind kind}) async {
  LibraryStore store = await LibraryStore.instance();
  if (!context.mounted) return;
  ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  void done(String message) => messenger.showSnackBar(SnackBar(content: Text(message)));

  await showOptionsSheet(
    context,
    title: "Add to",
    options: [
      SheetOption(
        icon: store.isFavourite(key) ? Icons.favorite : Icons.favorite_border,
        label: "Favourites",
        onTap: () async {
          if (store.isFavourite(key)) {
            done("Already in Favourites");
            return;
          }
          await store.toggleFavourite(key);
          done("Added to Favourites");
        },
      ),
      SheetOption(
        icon: Icons.fiber_new_outlined,
        label: "Latest",
        onTap: () async {
          await store.addToLatest(key);
          done("Added to Latest");
        },
      ),
      for (Playlist playlist in store.playlistsOf(kind))
        SheetOption(
          icon: Icons.queue_music,
          label: playlist.name,
          onTap: () async {
            bool added = await store.addToPlaylist(playlist.id, key);
            done(added ? "Added to ${playlist.name}" : "Already in ${playlist.name}");
          },
        ),
      SheetOption(
        icon: Icons.playlist_add,
        label: "New playlist…",
        onTap: () async {
          if (!context.mounted) return;
          String? name = await askPlaylistName(context);
          if (name == null) return;
          Playlist playlist = await store.createPlaylist(name, kind: kind);
          await store.addToPlaylist(playlist.id, key);
          done("Added to ${playlist.name}");
        },
      ),
    ],
  );
}
