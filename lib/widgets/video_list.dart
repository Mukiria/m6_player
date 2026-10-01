import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../screens/video_player_screen.dart';
import '../utils/format.dart';
import 'item_actions.dart';

/// A list of videos: all videos, favourites, Latest or a video playlist.
/// Tapping one plays the list from there; its ⋮ opens the options sheet.
class VideoList extends StatelessWidget {
  final List<AssetEntity> videos;
  final ItemList from;
  final String? playlistId;
  final String? header;
  final Future<void> Function()? onRefresh;

  const VideoList({super.key, required this.videos, this.from = ItemList.all, this.playlistId, this.header, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    String? header = this.header;
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
    Future<void> Function()? refresh = onRefresh;
    return refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
  }

  Widget _tile(BuildContext context, int index, ColorScheme colors) {
    AssetEntity video = videos[index];
    String title = videoTitle(video);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(videos: videos, index: index),
      )),
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
    _thumbnail = widget.video.thumbnailDataWithSize(ThumbnailSize(256, 144), quality: 80);
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
