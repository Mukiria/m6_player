import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../screens/video_player_screen.dart';
import '../services/app_settings.dart';
import '../services/library_store.dart';
import '../utils/format.dart';
import 'item_actions.dart';
import 'playlist_picker.dart';
import 'selection_bar.dart';

/// A list of videos: all videos, favourites, Latest or a video playlist.
/// Tapping one plays the list from there; its ⋮ opens the options sheet.
/// With [splitShorts], videos under 30 seconds go in a Shorts carousel above the
/// rest, and with [groupByDate] the rest sit under their day's heading.
class VideoList extends StatefulWidget {
  final List<AssetEntity> videos;
  final ItemList from;
  final String? playlistId;
  final String? header;
  final Future<void> Function()? onRefresh;
  final bool splitShorts;
  final bool groupByDate;

  const VideoList({
    super.key,
    required this.videos,
    this.from = ItemList.all,
    this.playlistId,
    this.header,
    this.onRefresh,
    this.splitShorts = false,
    this.groupByDate = false,
  });

  @override
  State<VideoList> createState() => _VideoListState();
}

class _VideoListState extends State<VideoList> {
  List<AssetEntity> get videos => widget.videos;
  ItemList get from => widget.from;
  String? get playlistId => widget.playlistId;
  final Set<String> _selected = {}; // Video ids picked by long-press for multi-select

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettings);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {}); // The list/grid choice changed
  }

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

  static const Duration _shortLimit = Duration(seconds: 30);

  bool _isShort(AssetEntity video) => video.videoDuration < _shortLimit;

  /// [videos] in runs that share a day (they arrive sorted by date, so a run is a day).
  List<(DateTime?, List<AssetEntity>)> _byDay(List<AssetEntity> videos) {
    List<(DateTime?, List<AssetEntity>)> groups = [];
    DateTime? day;
    for (AssetEntity video in videos) {
      DateTime created = video.createDateTime;
      DateTime d = DateTime(created.year, created.month, created.day);
      if (groups.isEmpty || d != day) {
        groups.add((d, []));
        day = d;
      }
      groups.last.$2.add(video);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    String? header = widget.header;
    ColorScheme colors = Theme.of(context).colorScheme;
    bool split = widget.splitShorts;
    List<AssetEntity> shorts = split ? videos.where(_isShort).toList() : [];
    List<AssetEntity> rest = split ? videos.where((v) => !_isShort(v)).toList() : videos;
    bool grid = split && AppSettings.instance.videoGrid; // Only the Videos section has the choice

    Widget list = LayoutBuilder(builder: (context, box) {
      int columns = box.maxWidth >= 600 ? 3 : 2;
      double cell = (box.maxWidth - 24 - 12 * (columns - 1)) / columns;
      List<Widget> slivers = [];
      if (!split && header != null) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(header, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          ),
        ));
      }
      if (shorts.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(child: _sectionHeading("Shorts", onTap: () => _openShorts(shorts))));
        slivers.add(SliverToBoxAdapter(child: _shortsCarousel(shorts)));
      }
      if (split && rest.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: _sectionHeading(
            "Videos",
            trailing: IconButton(
              tooltip: grid ? "Show as list" : "Show as grid",
              icon: Icon(grid ? Icons.view_list : Icons.grid_view, size: 28),
              onPressed: () => AppSettings.instance.setVideoGrid(!grid),
            ),
          ),
        ));
      }
      List<(DateTime?, List<AssetEntity>)> groups = widget.groupByDate ? _byDay(rest) : [(null, rest)];
      for (var (day, group) in groups) {
        if (day != null) {
          slivers.add(SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(formatDate(day), style: TextStyle(fontSize: 18, color: colors.onSurfaceVariant)),
            ),
          ));
        }
        slivers.add(grid
            ? SliverPadding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: cell * 9 / 16 + 52,
                  ),
                  itemCount: group.length,
                  itemBuilder: (context, index) => _gridTile(context, group, index, colors),
                ),
              )
            : SliverList.builder(
                itemCount: group.length,
                itemBuilder: (context, index) => _tile(context, group, index, colors),
              ));
      }
      slivers.add(SliverToBoxAdapter(child: SizedBox(height: 8)));
      return CustomScrollView(slivers: slivers);
    });
    Future<void> Function()? refresh = widget.onRefresh;
    Widget body = refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
    if (_selected.isEmpty) return body;
    return Column(children: [Expanded(child: body), _selectionBar()]);
  }

  /// A big bold section title, with a › that opens the whole section when [onTap] is given, and a [trailing] widget at the right.
  Widget _sectionHeading(String text, {VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 12, 12),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700))),
            if (onTap != null) Icon(Icons.chevron_right, size: 32),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  void _openShorts(List<AssetEntity> shorts) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text("Shorts")),
        body: VideoList(videos: shorts, from: from, playlistId: playlistId, header: "${shorts.length} shorts"),
      ),
    ));
  }

  /// Videos under 30 seconds, scrolling sideways, each cropped to portrait.
  Widget _shortsCarousel(List<AssetEntity> shorts) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: shorts.length,
        separatorBuilder: (context, i) => SizedBox(width: 12),
        itemBuilder: (context, index) {
          AssetEntity video = shorts[index];
          String title = videoTitle(video);
          bool selected = _selected.contains(video.id);
          return GestureDetector(
            onTap: () => _selected.isNotEmpty
                ? _toggleSelected(video)
                : Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(videos: shorts, index: index),
                  )),
            onLongPress: () => _toggleSelected(video),
            child: Semantics(
              selected: selected,
              label: title,
              child: Container(
                foregroundDecoration: selected
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                      )
                    : null,
                child: Stack(
                  children: [
                    VideoThumbnail(video: video, width: 126, height: 180, radius: 16, large: true),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton(
                        tooltip: "More",
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.more_vert, color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
                        onPressed: () => showVideoOptions(context, video, title, from: from, playlistId: playlistId),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// A video as a grid cell: a 16:9 thumbnail with its ⋮ over the corner, then the title.
  Widget _gridTile(BuildContext context, List<AssetEntity> list, int index, ColorScheme colors) {
    AssetEntity video = list[index];
    String title = videoTitle(video);
    bool selected = _selected.contains(video.id);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _selected.isNotEmpty
          ? _toggleSelected(video)
          : Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(videos: list, index: index),
            )),
      onLongPress: () => _toggleSelected(video),
      child: Semantics(
        selected: selected,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? colors.primary.withValues(alpha: 0.12) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    VideoThumbnail(video: video, width: box.maxWidth, height: box.maxWidth * 9 / 16, radius: 16),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: "More",
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.more_vert, color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
                        onPressed: () => showVideoOptions(context, video, title, from: from, playlistId: playlistId),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, List<AssetEntity> list, int index, ColorScheme colors) {
    AssetEntity video = list[index];
    String title = videoTitle(video);
    bool selected = _selected.contains(video.id);
    return InkWell(
      onTap: () => _selected.isNotEmpty
          ? _toggleSelected(video)
          : Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(videos: list, index: index),
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
            VideoThumbnail(video: video, width: 160, height: 90, radius: 16),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(
                    video.height > 0 ? "${video.height < video.width ? video.height : video.width}p" : "",
                    style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant),
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

  /// [large] is for the portrait Shorts crop: a bigger picture, in the video's own proportions.
  Future<Uint8List?> of(AssetEntity video, {bool large = false}) {
    String key = large ? '${video.id}@large' : video.id;
    Future<Uint8List?>? cached = _entries.remove(key);
    if (cached == null) {
      ThumbnailSize size = ThumbnailSize(256, 144);
      if (large) {
        double ratio = video.width > 0 && video.height > 0 ? video.height / video.width : 9 / 16;
        size = ThumbnailSize(480, (480 * ratio).round());
      }
      cached = video.thumbnailDataWithSize(size, quality: 80);
      // A failed or empty thumbnail isn't kept, so it's tried again next time.
      cached.then<void>((data) {
        if (data == null) _entries.remove(key);
      }, onError: (Object e) {
        _entries.remove(key);
      });
    }
    _entries[key] = cached; // Now the most recent
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
  final double radius;

  /// A larger picture, for a crop that shows only part of it.
  final bool large;

  const VideoThumbnail(
      {super.key, required this.video, required this.width, required this.height, this.radius = 8, this.large = false});

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  late Future<Uint8List?> _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = _thumbnails.of(widget.video, large: widget.large);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
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
