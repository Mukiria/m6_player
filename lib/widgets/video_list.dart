import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../screens/video_player_screen.dart';
import '../services/library_store.dart';
import '../utils/format.dart';
import 'item_actions.dart';
import 'playlist_picker.dart';
import 'selection_bar.dart';

/// A list of videos: all videos, favourites, Latest or a video playlist.
/// Tapping one plays the list from there; its ⋮ opens the options sheet.
class VideoList extends StatefulWidget {
  final List<AssetEntity> videos;
  final ItemList from;
  final String? playlistId;
  final String? header;
  final Future<void> Function()? onRefresh;

  const VideoList({super.key, required this.videos, this.from = ItemList.all, this.playlistId, this.header, this.onRefresh});

  @override
  State<VideoList> createState() => _VideoListState();
}

class _VideoListState extends State<VideoList> {
  List<AssetEntity> get videos => widget.videos;
  ItemList get from => widget.from;
  String? get playlistId => widget.playlistId;
  final Set<String> _selected = {}; // Video ids picked by long-press for multi-select

  List<String> get _selectedKeys => _selected.map(videoKey).toList();

  void _toggleSelected(AssetEntity video) {
    setState(() {
      if (!_selected.remove(video.id)) _selected.add(video.id);
    });
  }

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _selectionBar() => SelectionBar(
        count: _selected.length,
        onClose: () => setState(_selected.clear),
        onSelectAll: () => setState(() => _selected.addAll(videos.map((video) => video.id))),
        onFavourite: () async {
          LibraryStore store = await LibraryStore.instance();
          int added = await store.addAllToFavourites(_selectedKeys);
          setState(_selected.clear);
          _say("$added added to Favourites");
        },
        onAddTo: () async {
          await showAddToMany(context, keys: _selectedKeys, kind: MediaKind.video);
          if (mounted) setState(_selected.clear);
        },
        onHide: () async {
          LibraryStore store = await LibraryStore.instance();
          List<String> keys = _selectedKeys;
          await store.hideAll(keys);
          setState(_selected.clear);
          _say("${keys.length} hidden. Find them again under Hidden.");
        },
      );

  @override
  Widget build(BuildContext context) {
    String? header = widget.header;
    ColorScheme colors = Theme.of(context).colorScheme;
    Widget list = ListView.builder(
      padding: EdgeInsets.only(bottom: 8),
      itemCount: videos.length + (header == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (header != null && index == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(header, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          );
        }
        return _tile(context, index - (header == null ? 0 : 1), colors);
      },
    );
    Future<void> Function()? refresh = widget.onRefresh;
    Widget body = refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
    if (_selected.isEmpty) return body;
    return Column(children: [Expanded(child: body), _selectionBar()]);
  }

  Widget _tile(BuildContext context, int index, ColorScheme colors) {
    AssetEntity video = videos[index];
    String title = videoTitle(video);
    bool selected = _selected.contains(video.id);
    return InkWell(
      onTap: () => _selected.isNotEmpty
          ? _toggleSelected(video)
          : Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(videos: videos, index: index),
            )),
      onLongPress: () => _toggleSelected(video),
      child: Semantics(
        selected: selected,
        child: Container(
        color: selected ? colors.primary.withValues(alpha: 0.12) : null,
        child: Padding(
        padding: EdgeInsets.only(left: 16, top: 6, bottom: 6),
        child: Row(
          children: [
            VideoThumbnail(video: video, width: 128, height: 72),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15)),
                  SizedBox(height: 4),
                  Text(
                    video.height > 0 ? "${video.height < video.width ? video.height : video.width}p" : "",
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: "More",
              icon: Icon(Icons.more_vert),
              onPressed: () => showVideoOptions(context, video, title, from: from, playlistId: playlistId),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }
}

/// A video's file name without the extension ("Video" if the phone gives none).
String videoTitle(AssetEntity video) {
  String name = video.title ?? '';
  int dot = name.lastIndexOf('.');
  name = dot > 0 ? name.substring(0, dot) : name;
  return name.isEmpty ? "Video" : name;
}

/// Remembers the most recent thumbnails, so scrolling a list back up, switching
/// tabs or opening the carousel doesn't ask the phone to make them all again.
class _ThumbnailCache {
  static const int _capacity = 300; // About 3 MB of small JPEGs
  final Map<String, Future<Uint8List?>> _entries = {}; // Oldest first

  Future<Uint8List?> of(AssetEntity video) {
    Future<Uint8List?>? cached = _entries.remove(video.id);
    if (cached == null) {
      cached = video.thumbnailDataWithSize(ThumbnailSize(256, 144), quality: 80);
      // A failed or empty thumbnail isn't kept, so it's tried again next time.
      cached.then((data) {
        if (data == null) _entries.remove(video.id);
      }, onError: (Object e) => _entries.remove(video.id));
    }
    _entries[video.id] = cached; // Now the most recent
    if (_entries.length > _capacity) _entries.remove(_entries.keys.first);
    return cached;
  }
}

final _ThumbnailCache _thumbnails = _ThumbnailCache();

/// A video's thumbnail with its length in the corner, as in most video players.
class VideoThumbnail extends StatefulWidget {
  final AssetEntity video;
  final double width;
  final double height;

  const VideoThumbnail({super.key, required this.video, required this.width, required this.height});

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  late Future<Uint8List?> _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = _thumbnails.of(widget.video);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black12,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _thumbnail,
              builder: (context, snapshot) => snapshot.data == null
                  ? Icon(Icons.movie_outlined, color: Colors.white54)
                  : Image.memory(snapshot.data!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Text(
                formatDuration(widget.video.videoDuration),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
