import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import '../services/library_store.dart';
import '../services/player_service.dart';
import '../services/video_library.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/options_sheet.dart';
import '../widgets/video_list.dart';

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
  late List<AssetEntity> _queue; // What next/previous walk through
  static const double _carouselFraction = 0.6; // Share of the width one carousel page takes
  final PageController _carouselPages = PageController(viewportFraction: _carouselFraction);
  int _carouselShown = -1; // Which carousel page was last slid to
  bool _failed = false;
  bool _showControls = true;
  bool _isLandscape = false;
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  double _speed = 1.0; // Kept from one video to the next
  int _shape = 0; // Index into _shapes; kept from one video to the next
  static const List<String> _shapes = ["Fit", "Fill", "16:9", "4:3"];
  bool _hasSubtitles = false; // A subtitle file is loaded for this video
  bool _subtitlesOn = true;
  bool _locked = false; // Touch lock: only the unlock button responds
  bool _boosting = false; // Holding a finger down plays at 2x
  Timer? _hideTimer;
  Duration? _dragPosition; // While the user drags the seek bar

  // Sleep timer: pauses the video after a set time, or when this video ends
  Timer? _sleepTimer;
  DateTime? _sleepAt;
  bool _sleepAtEnd = false;
  bool get _sleepOn => _sleepAt != null || _sleepAtEnd;

  LibraryStore? _store;
  final List<StreamSubscription> _sessionSubscriptions = [];
  String? _countedKey; // The video already counted as played
  String? _loadedKey; // The video the controller holds, for saving its position
  Duration _lastSaved = Duration.zero;

  // Swipe gestures: up/down on the left changes brightness, on the right volume
  double _brightness = 0.5;
  double _volume = 0.5;
  bool _dragIsBrightness = true;
  IconData? _gestureIcon;
  String _gestureText = '';
  Timer? _gestureTimer;

  /// The video showing: from the list at [_index], or one from the up-next queue.
  late AssetEntity _video;

  /// True when there's a video to go to after this one (up next, or later in the list).
  bool get _hasNext => VideoLibrary.instance.upNext.isNotEmpty || _index < _queue.length - 1;

  /// Next video: the up-next queue (Play next / Play last) comes first, then the list.
  void _goNext() {
    AssetEntity? queued = VideoLibrary.instance.takeUpNext();
    if (queued != null) {
      _video = queued;
    } else {
      _index++;
      _video = _queue[_index];
    }
    _open();
  }

  @override
  void initState() {
    super.initState();
    _queue = widget.videos;
    _index = widget.index;
    _video = _queue[_index];
    // Music and video shouldn't play over each other.
    PlayerService.instance.player.pause();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    LibraryStore.instance().then((store) => _store = store);
    _loadLevels();
    _pauseWhenInterrupted();
    _open();
  }

  /// Pauses when headphones are unplugged (or Bluetooth disconnects) and when a call or another app takes over the sound.
  Future<void> _pauseWhenInterrupted() async {
    try {
      AudioSession session = await AudioSession.instance;
      if (!mounted) return;
      _sessionSubscriptions.addAll([
        session.becomingNoisyEventStream.listen((_) => _controller?.pause()),
        session.interruptionEventStream.listen((event) {
          if (event.begin && event.type != AudioInterruptionType.duck) _controller?.pause();
        }),
      ]);
    } catch (e) {
      debugPrint("Error listening for audio interruptions: $e");
    }
  }

  Future<void> _loadLevels() async {
    try {
      VolumeController.instance.showSystemUI = false; // We draw our own indicator
      _brightness = await ScreenBrightness().application;
      _volume = await VolumeController.instance.getVolume();
    } catch (e) {
      debugPrint("Error reading brightness/volume: $e");
    }
  }

  /// Remembers where the loaded video is, so it can carry on from there next time.
  /// Near the very start or end counts as "not started" / "finished".
  void _savePosition() {
    VideoPlayerController? controller = _controller;
    String? key = _loadedKey;
    if (controller == null || key == null || !controller.value.isInitialized) return;
    Duration position = controller.value.position;
    Duration duration = controller.value.duration;
    bool resumable = position > Duration(seconds: 5) && position < duration - Duration(seconds: 5);
    _store?.setPosition(key, resumable ? position : null);
    _lastSaved = position;
  }

  void _cancelSleep() {
    _sleepTimer?.cancel();
    _sleepAt = null;
    _sleepAtEnd = false;
  }

  void _setSleep(Duration? delay) {
    setState(() {
      _cancelSleep();
      if (delay == null) {
        _sleepAtEnd = true; // Stops the next video starting too; see _onTick
      } else {
        _sleepAt = DateTime.now().add(delay);
        _sleepTimer = Timer(delay, () {
          _controller?.pause();
          if (mounted) setState(() => _cancelSleep());
        });
      }
    });
    _showGesture(Icons.bedtime_outlined, delay == null ? "Sleep at end" : "Sleep in ${delay.inMinutes} min");
    _scheduleHide();
  }

  /// "12 min" left on the timer, "End", or null when it's off.
  String? get _sleepLabel {
    if (_sleepAtEnd) return "End";
    DateTime? at = _sleepAt;
    if (at == null) return null;
    return "${(at.difference(DateTime.now()).inSeconds / 60).ceil().clamp(1, 999)} min";
  }

  /// The picture in the chosen shape: Fit (whole picture), Fill (cropped to fill the screen), or stretched to 16:9 / 4:3.
  Widget _videoView(VideoPlayerController controller) {
    switch (_shapes[_shape]) {
      case "Fill":
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        );
      case "16:9":
        return AspectRatio(aspectRatio: 16 / 9, child: VideoPlayer(controller));
      case "4:3":
        return AspectRatio(aspectRatio: 4 / 3, child: VideoPlayer(controller));
      default:
        return AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller));
    }
  }

  void _nextShape() {
    setState(() => _shape = (_shape + 1) % _shapes.length);
    _showGesture(Icons.aspect_ratio, _shapes[_shape]);
    _scheduleHide();
  }

  // ------------------------------------------------------------ Subtitles

  /// Where this video's subtitle file is kept (a copy of the one the user picked).
  Future<Directory> _subtitleDir() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/subtitles').create(recursive: true);

  Future<List<File>> _savedSubtitleFiles() async {
    Directory dir = await _subtitleDir();
    return [for (String ext in ['srt', 'vtt']) File('${dir.path}/${_video.id}.$ext')].where((f) => f.existsSync()).toList();
  }

  /// Loads the subtitles saved for this video, if it has any.
  Future<void> _loadSavedSubtitles(VideoPlayerController controller) async {
    try {
      List<File> saved = await _savedSubtitleFiles();
      if (saved.isNotEmpty) await _applySubtitles(controller, saved.first);
    } catch (e) {
      debugPrint("Error loading subtitles: $e");
    }
  }

  Future<void> _applySubtitles(VideoPlayerController controller, File file) async {
    List<int> bytes = await file.readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes); // Older subtitle files are often not UTF-8
    }
    ClosedCaptionFile captions =
        file.path.endsWith('.vtt') ? WebVTTCaptionFile(text) : SubRipCaptionFile(text);
    await controller.setClosedCaptionFile(Future.value(captions));
    if (mounted) setState(() => _hasSubtitles = true);
  }

  /// Picks a .srt or .vtt file from the phone and keeps a copy for this video.
  Future<void> _pickSubtitles() async {
    VideoPlayerController? controller = _controller;
    if (controller == null) return;
    try {
      List<PlatformFile> picked = await FilePicker.pickFiles(type: FileType.any);
      String? path = picked.isEmpty ? null : picked.first.path;
      if (path == null) return;
      String ext = path.toLowerCase().endsWith('.vtt') ? 'vtt' : (path.toLowerCase().endsWith('.srt') ? 'srt' : '');
      if (ext.isEmpty) {
        _showGesture(Icons.error_outline, "Choose a .srt or .vtt file");
        return;
      }
      for (File old in await _savedSubtitleFiles()) {
        await old.delete();
      }
      File saved = await File(path).copy('${(await _subtitleDir()).path}/${_video.id}.$ext');
      await _applySubtitles(controller, saved);
      setState(() => _subtitlesOn = true);
      _showGesture(Icons.subtitles, "Subtitles loaded");
    } catch (e) {
      debugPrint("Error loading a subtitle file: $e");
      _showGesture(Icons.error_outline, "Couldn't read that file");
    }
  }

  Future<void> _removeSubtitles() async {
    for (File old in await _savedSubtitleFiles()) {
      await old.delete();
    }
    await _controller?.setClosedCaptionFile(null);
    if (mounted) setState(() => _hasSubtitles = false);
  }

  /// Subtitles and audio track choices.
  Future<void> _showSubtitleMenu() async {
    _hideTimer?.cancel();
    VideoPlayerController? controller = _controller;
    List<VideoAudioTrack> tracks = [];
    try {
      if (controller != null && controller.isAudioTrackSupportAvailable()) tracks = await controller.getAudioTracks();
    } catch (e) {
      debugPrint("Error reading audio tracks: $e");
    }
    if (!mounted) return;
    await showOptionsSheet(
      context,
      title: "Subtitles and audio",
      options: [
        SheetOption(icon: Icons.upload_file, label: "Load a subtitle file (.srt, .vtt)…", onTap: _pickSubtitles),
        if (_hasSubtitles)
          SheetOption(
            icon: _subtitlesOn ? Icons.subtitles_off_outlined : Icons.subtitles_outlined,
            label: _subtitlesOn ? "Turn subtitles off" : "Turn subtitles on",
            onTap: () => setState(() => _subtitlesOn = !_subtitlesOn),
          ),
        if (_hasSubtitles) SheetOption(icon: Icons.delete_outline, label: "Remove subtitles", onTap: _removeSubtitles),
        if (tracks.length > 1)
          for (VideoAudioTrack track in tracks)
            SheetOption(
              icon: track.isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              label: "Audio: ${_trackName(track, tracks.indexOf(track))}",
              onTap: () => controller?.selectAudioTrack(track.id),
            ),
      ],
    );
    _scheduleHide();
  }

  String _trackName(VideoAudioTrack track, int index) {
    String? label = track.label?.trim();
    if (label != null && label.isNotEmpty) return label;
    String? language = track.language;
    if (language != null && language.isNotEmpty && language != 'und') return language;
    return "Track ${index + 1}";
  }

  void _boostStart() {
    if (_controller == null) return;
    _boosting = true;
    _controller!.setPlaybackSpeed(2.0);
    _showGesture(Icons.fast_forward, "2.0x");
  }

  void _boostEnd() {
    if (!_boosting) return;
    _boosting = false;
    _controller?.setPlaybackSpeed(_speed);
  }

  String _speedLabel(double speed) => speed == speed.roundToDouble() ? speed.toStringAsFixed(1) : '$speed';

  void _showGesture(IconData icon, String text) {
    _gestureTimer?.cancel();
    setState(() {
      _gestureIcon = icon;
      _gestureText = text;
    });
    _gestureTimer = Timer(Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gestureIcon = null);
    });
  }

  void _dragStart(DragStartDetails details) {
    if (_locked) return;
    _dragIsBrightness = details.localPosition.dx < MediaQuery.of(context).size.width / 2;
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_locked) return;
    // A swipe across half the screen height covers the whole range
    double change = -details.delta.dy / (MediaQuery.of(context).size.height / 2);
    if (_dragIsBrightness) {
      _brightness = (_brightness + change).clamp(0.0, 1.0);
      ScreenBrightness().setApplicationScreenBrightness(_brightness).catchError((_) {});
      _showGesture(Icons.brightness_6, "${(_brightness * 100).round()}%");
    } else {
      _volume = (_volume + change).clamp(0.0, 1.0);
      VolumeController.instance.setVolume(_volume).catchError((_) {});
      _showGesture(_volume == 0 ? Icons.volume_off : Icons.volume_up, "${(_volume * 100).round()}%");
    }
  }

  /// The videos in the playing video's folder (null when the phone gives no folder or it holds just one).
  List<AssetEntity>? get _folderVideos {
    String? folder = _video.relativePath;
    if (folder == null || folder.isEmpty) return null;
    List<AssetEntity> videos = VideoLibrary.instance.videos.where((v) => v.relativePath == folder).toList();
    return videos.length > 1 ? videos : null;
  }

  /// Plays a video picked from the carousel; the folder becomes the queue if the list lacked it.
  void _playFromFolder(List<AssetEntity> folder, AssetEntity video) {
    if (video.id == _video.id) return;
    int inQueue = _queue.indexWhere((v) => v.id == video.id);
    if (inQueue >= 0) {
      _index = inQueue;
    } else {
      _queue = folder;
      _index = folder.indexWhere((v) => v.id == video.id);
    }
    _video = video;
    _open();
  }

  /// The folder's videos as pages, one and a bit on screen at a time: each swipe
  /// moves along by one video. Tapping one plays it; the playing one has a white outline.
  Widget _carousel(List<AssetEntity> folder) {
    int current = folder.indexWhere((v) => v.id == _video.id);
    // Slide to the playing video only when it changes, never while the user is swiping.
    if (current >= 0 && current != _carouselShown) {
      _carouselShown = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _carouselPages.hasClients) {
          _carouselPages.animateToPage(current, duration: Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        double pageWidth = constraints.maxWidth * _carouselFraction;
        double thumbWidth = pageWidth - 12;
        double thumbHeight = thumbWidth * 9 / 16;
        return SizedBox(
          height: thumbHeight + 16,
          child: PageView.builder(
            controller: _carouselPages,
            itemCount: folder.length,
            itemBuilder: (context, i) {
              bool selected = i == current;
              return Semantics(
                button: true,
                selected: selected,
                label: "${videoTitle(folder[i])}, ${formatDuration(folder[i].videoDuration)}${selected ? ", playing" : ""}",
                child: ExcludeSemantics(
                  child: GestureDetector(
                onTap: () => _playFromFolder(folder, folder[i]),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
                    ),
                    child: VideoThumbnail(
                        key: ValueKey(folder[i].id), video: folder[i], width: thumbWidth - 4, height: thumbHeight - 4),
                  ),
                ),
              ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _open() async {
    _savePosition();
    _hasSubtitles = false;
    VideoPlayerController? old = _controller;
    String key = videoKey(_video.id);
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
      _store ??= await LibraryStore.instance();
      Duration? resumeAt = _store?.positionOf(key);
      if (resumeAt != null && resumeAt < controller.value.duration - Duration(seconds: 5)) {
        await controller.seekTo(resumeAt);
        _showGesture(Icons.history, "Resumed at ${formatDuration(resumeAt)}");
      }
      _loadedKey = key;
      _lastSaved = resumeAt ?? Duration.zero;
      await controller.setPlaybackSpeed(_speed);
      await _loadSavedSubtitles(controller);
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
    if (_countedKey != _loadedKey && value.isPlaying && value.position >= (value.duration < Duration(seconds: 60) ? value.duration ~/ 2 : Duration(seconds: 30))) {
      _countedKey = _loadedKey;
      if (_loadedKey != null) _store?.recordPlay(_loadedKey!); // Counts towards the smart playlists
    }
    if (ended) {
      _store?.setPosition(_loadedKey!, null); // Watched to the end: next time starts over
      _lastSaved = Duration.zero;
    } else if ((value.position - _lastSaved).abs() >= Duration(seconds: 5)) {
      _savePosition();
    }
    if (ended && _sleepAtEnd) {
      setState(() => _cancelSleep()); // Sleep timer: stay on this video
      return;
    }
    if (ended && !_advancing && _hasNext) {
      _advancing = true;
      _goNext();
      Future.delayed(Duration(milliseconds: 500), () => _advancing = false);
      return;
    }
    PlayerService.instance.videoPlaying.value = value.isPlaying;
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
      _savePosition();
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
    PlayerService.instance.videoPlaying.value = false;
    _savePosition();
    for (StreamSubscription subscription in _sessionSubscriptions) {
      subscription.cancel();
    }
    _gestureTimer?.cancel();
    _sleepTimer?.cancel();
    ScreenBrightness().resetApplicationScreenBrightness().catchError((_) {});
    _hideTimer?.cancel();
    _carouselPages.dispose();
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([]); // Back to the app's normal rotation
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    VideoPlayerController? controller = _controller;
    bool ready = controller != null && controller.value.isInitialized;
    bool landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    List<AssetEntity>? folder = landscape ? null : _folderVideos; // Full screen when sideways

    Widget player = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          if (_locked) return;
          double width = MediaQuery.of(context).size.width;
          _skipBy(details.localPosition.dx < width / 2 ? -_skip : _skip);
        },
        onDoubleTap: () {}, // Needed for onDoubleTapDown to fire
        onLongPressStart: (_) => _locked ? null : _boostStart(),
        onLongPressEnd: (_) => _boostEnd(),
        onLongPressCancel: _boostEnd,
        onVerticalDragStart: _dragStart,
        onVerticalDragUpdate: _dragUpdate,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _failed
                  ? Text("Couldn't play this video.", style: TextStyle(color: Colors.white70))
                  : ready
                      ? _videoView(controller)
                      : CircularProgressIndicator(color: brandBlueLight),
            ),
            if (_hasSubtitles && _subtitlesOn && ready && controller.value.caption.text.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, _showControls ? 96 : 32),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Text(controller.value.caption.text,
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ),
            if (_locked && _showControls)
              SafeArea(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: IconButton(
                      tooltip: "Unlock",
                      iconSize: 32,
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      icon: Icon(Icons.lock, color: Colors.white),
                      onPressed: () {
                        setState(() => _locked = false);
                        _showGesture(Icons.lock_open, "Unlocked");
                        _scheduleHide();
                      },
                    ),
                  ),
                ),
              ),
            if (!_locked && (_showControls || _failed)) _controls(controller, ready),
            if (_gestureIcon != null)
              Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_gestureIcon, color: Colors.white, size: 32),
                      SizedBox(height: 6),
                      Text(_gestureText, style: TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

    return Scaffold(
      backgroundColor: Colors.black,
      body: folder == null
          ? player
          : Column(
              children: [
                Expanded(child: player),
                SafeArea(top: false, child: _carousel(folder)),
              ],
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
                IconButton(
                  tooltip: "Subtitles and audio",
                  icon: Icon(Icons.subtitles_outlined, color: _hasSubtitles && _subtitlesOn ? brandBlueLight : Colors.white),
                  onPressed: ready ? _showSubtitleMenu : null,
                ),
                IconButton(
                  tooltip: "Lock touch",
                  icon: Icon(Icons.lock_open, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _locked = true;
                      _showControls = false;
                    });
                    _showGesture(Icons.lock, "Locked: tap the screen to show the unlock button");
                  },
                ),
                PopupMenuButton<int>(
                  tooltip: "Sleep timer",
                  onOpened: _hideTimer?.cancel,
                  onCanceled: _scheduleHide,
                  onSelected: (minutes) {
                    if (minutes < 0) {
                      setState(_cancelSleep);
                      _scheduleHide();
                    } else {
                      _setSleep(minutes == 0 ? null : Duration(minutes: minutes));
                    }
                  },
                  itemBuilder: (context) => [
                    if (_sleepOn) PopupMenuItem(value: -1, child: Text("Turn off sleep timer")),
                    for (int minutes in [15, 30, 45, 60]) PopupMenuItem(value: minutes, child: Text("$minutes minutes")),
                    PopupMenuItem(value: 0, child: Text("End of this video")),
                  ],
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.bedtime_outlined, color: _sleepOn ? brandBlueLight : Colors.white),
                        if (_sleepLabel != null)
                          Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Text(_sleepLabel!, style: TextStyle(color: brandBlueLight, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 4),
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
                          _video = _queue[_index];
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
                  onPressed: _hasNext ? _goNext : null,
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
                      semanticFormatterCallback: (value) =>
                          "${formatDuration(Duration(milliseconds: value.round()))} of ${formatDuration(duration)}",
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
                    tooltip: "Picture shape: ${_shapes[_shape]}",
                    icon: Icon(Icons.aspect_ratio, color: Colors.white),
                    onPressed: ready ? _nextShape : null,
                  ),
                  PopupMenuButton<double>(
                    tooltip: "Playback speed",
                    initialValue: _speed,
                    onOpened: _hideTimer?.cancel,
                    onCanceled: _scheduleHide,
                    onSelected: (speed) {
                      setState(() => _speed = speed);
                      controller?.setPlaybackSpeed(speed);
                      _showGesture(Icons.speed, "${_speedLabel(speed)}x");
                      _scheduleHide();
                    },
                    itemBuilder: (context) => [
                      for (double speed in _speeds) PopupMenuItem(value: speed, child: Text("${_speedLabel(speed)}x")),
                    ],
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: 48, minHeight: 48), // A full-size touch target
                      child: Center(
                        child: Text("${_speedLabel(_speed)}x",
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
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
