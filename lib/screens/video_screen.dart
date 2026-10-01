import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../utils/format.dart';
import '../widgets/app_logo.dart';
import 'video_player_screen.dart';

/// The Video tab: every video on the phone, newest first, with thumbnails.
/// Nothing is copied; videos are played where they are.
class VideoScreen extends StatefulWidget {
  /// True while the Video tab is the one on screen.
  final bool isVisible;

  const VideoScreen({super.key, required this.isVisible});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  static const PermissionRequestOption _permissionOption = PermissionRequestOption(
    androidPermission: AndroidPermission(type: RequestType.video, mediaLocation: false),
  );

  List<AssetEntity> _videos = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _noPermission = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _loadIfNeeded();
  }

  @override
  void didUpdateWidget(VideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _loadIfNeeded();
  }

  /// Loads the list the first time the tab is opened, so the permission
  /// prompt doesn't appear at app start for people who only want music.
  void _loadIfNeeded() {
    if (!_hasLoaded && !_isLoading) _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    try {
      PermissionState permission = await PhotoManager.requestPermissionExtend(requestOption: _permissionOption);
      if (!permission.hasAccess) {
        if (!mounted) return;
        setState(() {
          _noPermission = true;
          _isLoading = false;
          _hasLoaded = true;
        });
        return;
      }
      int count = await PhotoManager.getAssetCount(type: RequestType.video);
      List<AssetEntity> videos = count == 0
          ? []
          : await PhotoManager.getAssetListRange(start: 0, end: count, type: RequestType.video);
      videos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _noPermission = false;
      });
    } catch (e) {
      debugPrint("Error loading videos: $e");
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasLoaded = true;
    });
  }

  void _play(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => VideoPlayerScreen(videos: _videos, index: index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: AppLogo(),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: "Refresh",
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadVideos,
          ),
        ],
      ),
      body: _isLoading && _videos.isEmpty
          ? Center(child: CircularProgressIndicator())
          : _noPermission
              ? _message(
                  colors,
                  icon: Icons.video_library_outlined,
                  text: "Allow m6 player to see your videos to play them here.",
                  buttonLabel: "Allow access",
                  onPressed: () async {
                    // A second request is usually blocked by the system: send people to Settings.
                    await PhotoManager.openSetting();
                  },
                )
              : _videos.isEmpty
                  ? _message(colors, icon: Icons.videocam_off_outlined, text: "No videos on this phone yet.")
                  : RefreshIndicator(
                      onRefresh: _loadVideos,
                      child: ListView.builder(
                        padding: EdgeInsets.only(bottom: 8),
                        itemCount: _videos.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text("Videos (${_videos.length})",
                                  style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
                            );
                          }
                          return _videoTile(index - 1, colors);
                        },
                      ),
                    ),
    );
  }

  Widget _message(ColorScheme colors,
      {required IconData icon, required String text, String? buttonLabel, VoidCallback? onPressed}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colors.onSurfaceVariant),
            SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (buttonLabel != null) ...[
              SizedBox(height: 20),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _videoTile(int index, ColorScheme colors) {
    AssetEntity video = _videos[index];
    return InkWell(
      onTap: () => _play(index),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            VideoThumbnail(video: video, width: 128, height: 72),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(videoTitle(video), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15)),
                  SizedBox(height: 4),
                  Text(
                    video.height > 0 ? "${video.height < video.width ? video.height : video.width}p" : "",
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
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
