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

  /// Every row is this tall, so a song's position in the list is known exactly.
  static const double _rowHeight = 72;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentPath = _service.currentSongPath;
    _isPlaying = _service.player.playing;
    _subscriptions.addAll([
      _service.player.playerStateStream.listen((state) => setState(() => _isPlaying = state.playing)),
      _service.currentItemStream.listen((_) {
        String? path = _service.currentSongPath;
        if (path == _currentPath) return;
        setState(() => _currentPath = path);
        _scrollToPlaying(animate: true); // Next, previous or a song ending moves the list along
      }),
    ]);
    // Opening the list shows the playing song at the top straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPlaying(animate: false));
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onStoreChanged);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onStoreChanged() => setState(() {});

  @override
  void didUpdateWidget(SongList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new sort (or songs added or removed) moves the playing song: put it back on top.
    bool sameOrder = oldWidget.songs.length == widget.songs.length &&
        Iterable.generate(widget.songs.length).every((i) => oldWidget.songs[i].path == widget.songs[i].path);
    if (!sameOrder) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPlaying(animate: true));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _store?.removeListener(_onStoreChanged);
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the playing song (if it's in this list) to the top of the list.
  void _scrollToPlaying({required bool animate}) {
    int index = widget.songs.indexWhere((song) => song.path == _currentPath);
    if (index < 0 || !_scroll.hasClients) return;
    double offset = (index * _rowHeight).clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(offset, duration: Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(offset);
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(header, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          ),
        Expanded(
          child: LayoutBuilder(
            // Room under the last song so that any song, even the last, can sit at the top.
            builder: (context, constraints) => ListView.builder(
              controller: _scroll,
              itemExtent: _rowHeight,
              padding: EdgeInsets.only(bottom: (constraints.maxHeight - _rowHeight).clamp(8.0, double.infinity)),
              itemCount: widget.songs.length,
              itemBuilder: (context, index) => _songTile(index, colors),
            ),
          ),
        ),
      ],
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
