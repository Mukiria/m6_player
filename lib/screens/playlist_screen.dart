import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/song_list.dart';

/// One playlist: its songs in the order they were added, a Play button, and
/// rename or delete in the ⋮ menu.
class PlaylistScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final MusicLibrary _library = MusicLibrary.instance;
  LibraryStore? _store;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onChanged);
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onChanged);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _library.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _rename(Playlist playlist) async {
    String? name = await askPlaylistName(context, title: "Rename playlist", initial: playlist.name);
    if (name != null) await _store?.renamePlaylist(playlist.id, name);
  }

  Future<void> _delete(Playlist playlist) async {
    bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Delete playlist?"),
            content: Text("Delete \"${playlist.name}\"? The songs stay in your library."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Delete")),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    PlayerService.instance.forgetQueue(playlist.id);
    await _store?.deletePlaylist(playlist.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Playlist? playlist = _store?.playlist(widget.playlistId);
    if (playlist == null) return Scaffold(appBar: AppBar());
    ColorScheme colors = Theme.of(context).colorScheme;
    // Songs deleted from the library are already gone from the playlist; skip any stragglers.
    List<File> songs = playlist.songs.map(_library.songNamed).whereType<File>().toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: "More",
            onSelected: (action) => action == "rename" ? _rename(playlist) : _delete(playlist),
            itemBuilder: (context) => [
              PopupMenuItem(value: "rename", child: Text("Rename")),
              PopupMenuItem(value: "delete", child: Text("Delete playlist")),
            ],
          ),
        ],
      ),
      floatingActionButton: songs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => PlayerService.instance.playQueue(playlist.id, songs, 0),
              icon: Icon(Icons.play_arrow),
              label: Text("Play"),
            ),
      body: songs.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "This playlist is empty. Add songs from the Songs list with their ⋮ menu.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            )
          : SongList(
              songs: songs,
              queueId: playlist.id,
              playlistId: playlist.id,
              header: "${songs.length} ${songs.length == 1 ? "song" : "songs"}",
            ),
    );
  }
}
