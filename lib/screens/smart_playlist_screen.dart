import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/video_library.dart';
import '../widgets/song_list.dart';
import '../widgets/video_list.dart';

/// Playlists the app fills in by itself from how you listen and watch.
enum SmartPlaylist {
  mostPlayed('Most played', Icons.trending_up, 'What you play the most'),
  recentlyPlayed('Recently played', Icons.history, 'What you played last'),
  recentlyAdded('Recently added', Icons.fiber_new_outlined, 'The newest in your library'),
  neverPlayed('Never played', Icons.visibility_off_outlined, 'Not played yet');

  final String label;
  final IconData icon;
  final String description;
  const SmartPlaylist(this.label, this.icon, this.description);

  /// How many items the "most", "recently" lists hold.
  static const int limit = 50;

  /// Sorts [items] (given newest-added first) into this playlist.
  List<T> pick<T>(List<T> items, String Function(T) keyOf, LibraryStore? store) {
    int plays(T item) => store?.playCount(keyOf(item)) ?? 0;
    DateTime? last(T item) => store?.lastPlayed(keyOf(item));
    switch (this) {
      case mostPlayed:
        List<T> played = items.where((item) => plays(item) > 0).toList();
        played.sort((a, b) {
          int byCount = plays(b).compareTo(plays(a));
          return byCount != 0 ? byCount : last(b)!.compareTo(last(a)!);
        });
        return played.take(limit).toList();
      case recentlyPlayed:
        List<T> played = items.where((item) => last(item) != null).toList();
        played.sort((a, b) => last(b)!.compareTo(last(a)!));
        return played.take(limit).toList();
      case recentlyAdded:
        return items.take(limit).toList();
      case neverPlayed:
        return items.where((item) => plays(item) == 0).toList();
    }
  }
}

/// The four smart playlists as rows, for the top of a Playlists tab.
class SmartPlaylistTiles extends StatelessWidget {
  final MediaKind kind;

  const SmartPlaylistTiles({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (SmartPlaylist smart in SmartPlaylist.values)
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(48 * 0.08),
              ),
              child: Icon(smart.icon, color: colors.primary),
            ),
            title: Text(smart.label),
            subtitle: Text(smart.description, style: TextStyle(color: colors.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => SmartPlaylistScreen(kind: kind, smart: smart)),
            ),
          ),
        Divider(),
      ],
    );
  }
}

/// One smart playlist's songs or videos. It's worked out when the page opens,
/// so it doesn't reshuffle while something is playing.
class SmartPlaylistScreen extends StatefulWidget {
  final MediaKind kind;
  final SmartPlaylist smart;

  const SmartPlaylistScreen({super.key, required this.kind, required this.smart});

  @override
  State<SmartPlaylistScreen> createState() => _SmartPlaylistScreenState();
}

class _SmartPlaylistScreenState extends State<SmartPlaylistScreen> {
  List<File> _songs = [];
  List<AssetEntity> _videos = [];

  @override
  void initState() {
    super.initState();
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      setState(() {
        if (widget.kind == MediaKind.audio) {
          // The library lists songs oldest first; the smart lists want newest first.
          List<File> songs = MusicLibrary.instance.songs.reversed.where((s) => !store.isHidden(songKey(s))).toList();
          _songs = widget.smart.pick<File>(songs, songKey, store);
        } else {
          List<AssetEntity> videos = VideoLibrary.instance.videos.where((v) => !store.isHidden(videoKey(v.id))).toList();
          _videos = widget.smart.pick<AssetEntity>(videos, (v) => videoKey(v.id), store);
        }
      });
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool songs = widget.kind == MediaKind.audio;
    int count = songs ? _songs.length : _videos.length;
    String noun = songs ? (count == 1 ? "song" : "songs") : (count == 1 ? "video" : "videos");
    return Scaffold(
      appBar: AppBar(title: Text(widget.smart.label)),
      body: count == 0
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  widget.smart == SmartPlaylist.neverPlayed
                      ? "You've played everything."
                      : "Nothing here yet.\nIt fills in as you ${songs ? "listen" : "watch"}.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            )
          : songs
              ? SongList(songs: _songs, queueId: 'smart:${widget.smart.name}', header: "$count $noun")
              : VideoList(videos: _videos, header: "$count $noun"),
    );
  }
}
