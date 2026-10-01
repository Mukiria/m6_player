import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../services/track_info.dart';
import 'artwork.dart';
import 'playlist_picker.dart';

/// A list of songs: all songs, favourites or one playlist. Tapping a song plays
/// this list from that song ([queueId] names the list for the player); tapping
/// the playing song pauses or resumes it. Each song's ⋮ menu has Play,
/// favourites, Add to playlist, Remove from this playlist (for a playlist) and
/// Delete from m6 player.
class SongList extends StatefulWidget {
  final List<File> songs;
  final String queueId;

  /// Set when this list is a playlist, to offer "Remove from this playlist".
  final String? playlistId;

  /// Line above the list, such as "Songs (12)".
  final String? header;

  const SongList({super.key, required this.songs, required this.queueId, this.playlistId, this.header});

  @override
  State<SongList> createState() => _SongListState();
}

class _SongListState extends State<SongList> {
  final PlayerService _service = PlayerService.instance;
  final TrackInfoService _tracks = TrackInfoService.instance;
  final List<StreamSubscription> _subscriptions = [];
  LibraryStore? _store;

  String? _currentPath; // The song playing now
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _currentPath = _service.currentSongPath;
    _isPlaying = _service.player.playing;
    _subscriptions.addAll([
      _service.player.playerStateStream.listen((state) => setState(() => _isPlaying = state.playing)),
      _service.currentItemStream.listen((_) => setState(() => _currentPath = _service.currentSongPath)),
    ]);
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onStoreChanged);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onStoreChanged() => setState(() {});

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  /// Tapping a song plays it; tapping the current song pauses or resumes it.
  Future<void> _togglePlay(int index) async {
    File song = widget.songs[index];
    try {
      if (_currentPath == song.path && _service.queueId == widget.queueId) {
        _isPlaying ? await _service.player.pause() : await _service.resume();
      } else {
        await _service.playQueue(widget.queueId, widget.songs, index);
      }
    } catch (e) {
      debugPrint("Error playing file: $e");
    }
  }

  Future<void> _delete(File song) async {
    bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Delete song?"),
            content: Text("Delete \"${_tracks.infoFor(song).title}\" from m6 player? "
                "It's also removed from your favourites and playlists. The original file on your device is not affected."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Delete")),
            ],
          ),
        ) ??
        false;
    if (confirmed) await MusicLibrary.instance.delete(song);
  }

  /// Takes the song off this playlist. If the playlist is playing, it keeps
  /// playing as it was; the change applies the next time it's started.
  Future<void> _removeFromPlaylist(File song) async {
    await _store?.removeFromPlaylist(widget.playlistId!, songKey(song));
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    String? header = widget.header;
    return ListView.builder(
      padding: EdgeInsets.only(bottom: 8),
      itemCount: widget.songs.length + (header == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (header != null && index == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(header, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          );
        }
        return _songTile(index - (header == null ? 0 : 1), colors);
      },
    );
  }

  Widget _songTile(int index, ColorScheme colors) {
    File song = widget.songs[index];
    TrackInfo info = _tracks.infoFor(song);
    bool isCurrent = _currentPath == song.path;
    bool isFavourite = _store?.isFavourite(songKey(song)) ?? false;
    return ListTile(
      contentPadding: EdgeInsets.only(left: 16, right: 4),
      leading: Stack(
        children: [
          Artwork(size: 48, coverPath: info.coverPath),
          // The playing song gets an equaliser (or pause) badge over its cover.
          if (isCurrent)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(48 * 0.08)),
              child: Icon(_isPlaying ? Icons.graphic_eq : Icons.pause, color: Colors.white),
            ),
        ],
      ),
      title: Text(
        info.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? colors.primary : null,
          fontWeight: isCurrent ? FontWeight.w600 : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (isFavourite) ...[
            Icon(Icons.favorite, size: 14, color: colors.primary),
            SizedBox(width: 4),
          ],
          Expanded(
            child: Text(info.subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant)),
          ),
        ],
      ),
      onTap: () => _togglePlay(index),
      trailing: PopupMenuButton<String>(
        tooltip: "More",
        icon: Icon(Icons.more_vert),
        onSelected: (action) {
          switch (action) {
            case "play":
              _togglePlay(index);
            case "favourite":
              _store?.toggleFavourite(songKey(song));
            case "playlist":
              showAddToPlaylist(context, song);
            case "unlist":
              _removeFromPlaylist(song);
            case "delete":
              _delete(song);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: "play", child: Text(isCurrent && _isPlaying ? "Pause" : "Play")),
          PopupMenuItem(
            value: "favourite",
            child: Text(isFavourite ? "Remove from favourites" : "Add to favourites"),
          ),
          PopupMenuItem(value: "playlist", child: Text("Add to playlist…")),
          if (widget.playlistId != null) PopupMenuItem(value: "unlist", child: Text("Remove from this playlist")),
          PopupMenuItem(value: "delete", child: Text("Delete from m6 player")),
        ],
      ),
    );
  }
}
