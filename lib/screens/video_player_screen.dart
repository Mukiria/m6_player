import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'video_screen.dart';

/// Full-screen video player. Tap to show or hide the controls; double-tap the
/// left or right side to go back or forward 10 seconds. Plays the next video
/// in the list when one ends.
class VideoPlayerScreen extends StatefulWidget {
  final List<AssetEntity> videos;
  final int index;

  const VideoPlayerScreen({super.key, required this.videos, required this.index});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  static const Duration _skip = Duration(seconds: 10);

  VideoPlayerController? _controller;
  late int _index;
  bool _failed = false;
  bool _showControls = true;
  bool _isLandscape = false;
  Timer? _hideTimer;
  Duration? _dragPosition; // While the user drags the seek bar

  AssetEntity get _video => widget.videos[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    // Music and video shouldn't play over each other.
    PlayerService.instance.player.pause();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _open();
  }

  Future<void> _open() async {
    VideoPlayerController? old = _controller;
    setState(() {
      _controller = null;
      _failed = false;
      _dragPosition = null;
    });
    await old?.dispose();
    try {
      File? file = await _video.file;
      if (file == null) throw Exception("Video file not available");
      VideoPlayerController controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      await controller.play();
      _scheduleHide();
    } catch (e) {
      debugPrint("Error opening video: $e");
      if (mounted) setState(() => _failed = true);
    }
  }

  bool _advancing = false;

  void _onTick() {
    VideoPlayerController? controller = _controller;
    if (controller == null || !mounted) return;
    VideoPlayerValue value = controller.value;
    bool ended = value.isInitialized && !value.isPlaying && value.position >= value.duration && value.duration > Duration.zero;
    if (ended && !_advancing && _index < widget.videos.length - 1) {
      _advancing = true;
      _index++;
      _open().whenComplete(() => _advancing = false);
      return;
    }
    setState(() {}); // Position, playing state
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _togglePlay() {
    VideoPlayerController? controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
      _hideTimer?.cancel();
    } else {
      if (controller.value.position >= controller.value.duration) controller.seekTo(Duration.zero);
      controller.play();
      _scheduleHide();
    }
    setState(() => _showControls = true);
  }

  void _skipBy(Duration offset) {
    VideoPlayerController? controller = _controller;
    if (controller == null) return;
    Duration target = controller.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > controller.value.duration) target = controller.value.duration;
    controller.seekTo(target);
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    SystemChrome.setPreferredOrientations(_isLandscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([]); // Back to the app's normal rotation
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    VideoPlayerController? controller = _controller;
    bool ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          double width = MediaQuery.of(context).size.width;
          _skipBy(details.localPosition.dx < width / 2 ? -_skip : _skip);
        },
        onDoubleTap: () {}, // Needed for onDoubleTapDown to fire
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _failed
                  ? Text("Couldn't play this video.", style: TextStyle(color: Colors.white70))
                  : ready
                      ? AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller))
                      : CircularProgressIndicator(color: brandBlueLight),
            ),
            if (_showControls || _failed) _controls(controller, ready),
          ],
        ),
      ),
    );
  }

  Widget _controls(VideoPlayerController? controller, bool ready) {
    Duration duration = ready ? controller!.value.duration : Duration.zero;
    Duration position = _dragPosition ?? (ready ? controller!.value.position : Duration.zero);
    if (position > duration) position = duration;
    bool isPlaying = ready && controller!.value.isPlaying;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
          stops: [0, 0.25, 0.7, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar: back and the video's name
            Row(
              children: [
                IconButton(
                  tooltip: "Back",
                  icon: Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(videoTitle(_video), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                ),
                SizedBox(width: 16),
              ],
            ),
            Spacer(),
            // Centre: previous video, play/pause, next video
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: "Previous video",
                  iconSize: 36,
                  icon: Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: _index > 0
                      ? () {
                          _index--;
                          _open();
                        }
                      : null,
                ),
                SizedBox(width: 24),
                Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black38),
                  child: IconButton(
                    tooltip: isPlaying ? "Pause" : "Play",
                    iconSize: 48,
                    icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                    onPressed: ready ? _togglePlay : null,
                  ),
                ),
                SizedBox(width: 24),
                IconButton(
                  tooltip: "Next video",
                  iconSize: 36,
                  icon: Icon(Icons.skip_next, color: Colors.white),
                  onPressed: _index < widget.videos.length - 1
                      ? () {
                          _index++;
                          _open();
                        }
                      : null,
                ),
              ],
            ),
            Spacer(),
            // Bottom: times, seek bar and rotate
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(formatDuration(position), style: TextStyle(color: Colors.white, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: position.inMilliseconds.toDouble(),
                      max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                      activeColor: brandBlueLight,
                      inactiveColor: Colors.white24,
                      onChanged: ready
                          ? (value) {
                              _hideTimer?.cancel();
                              setState(() => _dragPosition = Duration(milliseconds: value.round()));
                            }
                          : null,
                      onChangeEnd: (value) {
                        controller?.seekTo(Duration(milliseconds: value.round()));
                        setState(() => _dragPosition = null);
                        _scheduleHide();
                      },
                    ),
                  ),
                  Text(formatDuration(duration), style: TextStyle(color: Colors.white, fontSize: 12)),
                  IconButton(
                    tooltip: _isLandscape ? "Portrait" : "Landscape",
                    icon: Icon(Icons.screen_rotation, color: Colors.white),
                    onPressed: _toggleOrientation,
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
