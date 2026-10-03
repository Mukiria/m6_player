import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../services/video_library.dart';
import '../widgets/item_actions.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/song_list.dart';
import '../widgets/tab_background.dart';
import '../widgets/video_list.dart';
import 'video_player_screen.dart';

/// One playlist (songs or videos): its items in the order they were added, a
/// Play button, and rename or delete in the ⋮ menu. Hidden items are left out.
class PlaylistScreen extends StatefulWidget {
  final String playlistId;

  const PlaylistScreen({super.key, required this.playlistId});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final MusicLibrary _library = MusicLibrary.instance;
  final VideoLibrary _videos = VideoLibrary.instance;
  LibraryStore? _store;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onChanged);
    _videos.addListener(_onChanged);
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
    _videos.removeListener(_onChanged);
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
    bool isVideo = playlist.kind == MediaKind.video;
    List<String> keys = playlist.songs.where((key) => !(_store?.isHidden(key) ?? false)).toList();
    // Deleted items are already gone from the playlist; skip any stragglers.
    List<File> songs = isVideo ? [] : keys.map(_library.songNamed).whereType<File>().toList();
    List<AssetEntity> videos =
        isVideo ? keys.map(videoIdOf).whereType<String>().map(_videos.videoById).whereType<AssetEntity>().toList() : [];
    int count = isVideo ? videos.length : songs.length;
    String noun = isVideo ? (count == 1 ? "video" : "videos") : (count == 1 ? "song" : "songs");

    return TabBackground(
      image: 'assets/backgrounds/transfer.jpg',
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(playlist.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: "More",
            onSelected: (action) => switch (action) {
              "rename" => _rename(playlist),
              "cover" => chooseCoverPhoto(context, playlist),
              "removeCover" => removeCoverPhoto(playlist),
              _ => _delete(playlist),
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: "rename", child: Text("Rename")),
              PopupMenuItem(value: "cover", child: Text(playlist.coverPath == null ? "Add cover photo" : "Change cover photo")),
              if (playlist.coverPath != null) PopupMenuItem(value: "removeCover", child: Text("Remove cover photo")),
              PopupMenuItem(value: "delete", child: Text("Delete playlist")),
            ],
          ),
        ],
      ),
      floatingActionButton: count == 0
          ? null
          : isVideo
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(videos: videos, index: 0),
                  )),
                  icon: Icon(Icons.play_arrow),
                  label: Text("Play"),
                )
              : _playButton(playlist, songs),
      body: count == 0
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "This playlist is empty. Add ${isVideo ? "videos" : "songs"} with their ⋮ menu, Add to….",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            )
          : isVideo
              ? VideoList(videos: videos, from: ItemList.playlist, playlistId: playlist.id, header: "$count $noun")
              : SongList(
                  songs: songs,
                  queueId: playlist.id,
                  from: ItemList.playlist,
                  playlistId: playlist.id,
                  header: "$count $noun",
                ),
      ),
    );
  }

  /// Play, or Pause while this playlist is the one playing.
  Widget _playButton(Playlist playlist, List<File> songs) {
    PlayerService service = PlayerService.instance;
    // Rebuilds when playback starts or stops, and when another list takes over
    return StreamBuilder<PlayerState>(
      stream: service.player.playerStateStream,
      builder: (context, _) => StreamBuilder(
        stream: service.currentItemStream,
        builder: (context, _) {
          bool mine = service.isLibraryActive && service.queueId == playlist.id;
          bool playing = mine && service.player.playing;
          return FloatingActionButton.extended(
            onPressed: () {
              if (playing) {
                service.player.pause();
              } else if (mine) {
                service.resume();
              } else {
                service.playQueue(playlist.id, songs, 0);
              }
            },
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            label: Text(playing ? "Pause" : "Play"),
          );
        },
      ),
    );
  }
}
