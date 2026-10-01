import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/track_info.dart';
import '../services/video_library.dart';
import '../widgets/artwork.dart';
import '../widgets/video_list.dart';

/// Songs and videos taken out of view: Hidden ones (left out of every list)
/// and Filtered-out ones (left out of the Songs or Videos list only), each with
/// a button to bring it back.
class HiddenScreen extends StatefulWidget {
  const HiddenScreen({super.key});

  @override
  State<HiddenScreen> createState() => _HiddenScreenState();
}

class _HiddenScreenState extends State<HiddenScreen> {
  LibraryStore? _store;

  @override
  void initState() {
    super.initState();
    VideoLibrary.instance.addListener(_onChanged);
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onChanged);
      setState(() => _store = store);
      // Hidden videos need the phone's video list to show their names.
      VideoLibrary videos = VideoLibrary.instance;
      bool hasVideos = [...store.hidden, ...store.filteredOut].any((key) => videoIdOf(key) != null);
      if (hasVideos && !videos.hasLoaded) videos.load();
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    VideoLibrary.instance.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    LibraryStore? store = _store;
    List<String> hidden = store?.hidden.toList() ?? [];
    List<String> filtered = store?.filteredOut.toList() ?? [];
    ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text("Hidden & filtered")),
      body: store == null
          ? Center(child: CircularProgressIndicator())
          : hidden.isEmpty && filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text("Nothing is hidden or filtered out.",
                        textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
                  ),
                )
              : ListView(
                  children: [
                    if (hidden.isNotEmpty) ...[
                      _heading("Hidden", "Left out of every list", colors),
                      for (String key in hidden) _row(key, "Unhide", () => store.unhide(key)),
                    ],
                    if (filtered.isNotEmpty) ...[
                      _heading("Filtered out", "Left out of the Songs or Videos list", colors),
                      for (String key in filtered) _row(key, "Restore", () => store.restoreFilteredOut(key)),
                    ],
                  ],
                ),
    );
  }

  Widget _heading(String title, String subtitle, ColorScheme colors) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.primary)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ],
        ),
      );

  /// A hidden or filtered-out song or video, with its restore button.
  Widget _row(String key, String action, VoidCallback onRestore) {
    String? videoId = videoIdOf(key);
    Widget leading;
    String title;
    String subtitle;
    if (videoId != null) {
      AssetEntity? video = VideoLibrary.instance.videoById(videoId);
      leading = video == null
          ? Icon(Icons.movie_outlined, size: 40)
          : VideoThumbnail(video: video, width: 64, height: 36);
      title = video == null ? "Video" : videoTitle(video);
      subtitle = "Video";
    } else {
      File? song = MusicLibrary.instance.songNamed(key);
      TrackInfo? info = song == null ? null : TrackInfoService.instance.infoFor(song);
      leading = Artwork(size: 40, coverPath: info?.coverPath);
      title = info?.title ?? key;
      subtitle = info == null ? "Song" : "Song · ${info.subtitle}";
    }
    return ListTile(
      leading: leading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: TextButton(onPressed: onRestore, child: Text(action)),
    );
  }
}
