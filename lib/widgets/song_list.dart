import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/player_service.dart';
import '../services/track_info.dart';
import 'artwork.dart';
import 'item_actions.dart';

/// A list of songs: all songs, favourites, Latest or one playlist. Tapping a
/// song plays this list from that song ([queueId] names the list for the
/// player); tapping the playing song pauses or resumes it. Each song's ⋮
/// opens its options sheet (see item_actions.dart).
class SongList extends StatefulWidget {
  final List<File> songs;
  final String queueId;

  /// Which list this is, for the options sheet's "Filter out".
  final ItemList from;

  /// Set when this list is a playlist.
  final String? playlistId;

  /// Line above the list, such as "Songs (12)".
  final String? header;

  const SongList(
      {super.key, required this.songs, required this.queueId, this.from = ItemList.all, this.playlistId, this.header});

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
      if (_currentPath == song.path) {
        _isPlaying ? await _service.player.pause() : await _service.resume();
      } else {
        await _service.playQueue(widget.queueId, widget.songs, index);
      }
    } catch (e) {
      debugPrint("Error playing file: $e");
    }
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
      trailing: IconButton(
        tooltip: "More",
        icon: Icon(Icons.more_vert),
        onPressed: () => showSongOptions(context, song, from: widget.from, playlistId: widget.playlistId),
      ),
    );
  }
}
