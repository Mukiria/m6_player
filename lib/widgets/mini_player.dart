import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import '../screens/now_playing_screen.dart';
import '../services/player_service.dart';
import 'artwork.dart';

/// Strip above the navigation bar showing what is playing, with play/pause.
/// Tapping it opens the full Now Playing screen. Hidden until something plays.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final PlayerService _service = PlayerService.instance;
  AudioPlayer get _audioPlayer => _service.player;
  final List<StreamSubscription> _subscriptions = [];

  MediaItem? _item;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _item = _service.currentItem;
    _isPlaying = _audioPlayer.playing;
    _subscriptions.addAll([
      _service.currentItemStream.listen((item) => setState(() => _item = item)),
      _audioPlayer.playerStateStream.listen((state) => setState(() => _isPlaying = state.playing)),
      _audioPlayer.positionStream.listen((position) => setState(() => _position = position)),
      _audioPlayer.durationStream.listen((duration) => setState(() => _duration = duration ?? Duration.zero)),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _openNowPlaying() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => const NowPlayingScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    MediaItem? item = _item;
    if (item == null) return SizedBox.shrink();

    bool isRadio = isRadioItem(item);
    bool hasLength = _duration.inMilliseconds > 0;
    double progress = hasLength ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;

    // Sits on the orange bottom block (see HomeScreen), so it's white on transparent.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openNowPlaying,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Artwork(size: 44, isRadio: isRadio, coverPath: item.artUri?.toFilePath()),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                        Text(itemSubtitle(item), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _isPlaying ? 'Pause' : 'Play',
                    color: Colors.white,
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () => _isPlaying ? _audioPlayer.pause() : _service.resume(),
                  ),
                  if (!isRadio)
                    IconButton(
                      tooltip: 'Next',
                      color: Colors.white,
                      icon: Icon(Icons.skip_next),
                      onPressed: _service.next,
                    ),
                ],
              ),
              // Progress track (songs and videos have a length; a radio stream doesn't)
              Padding(
                padding: EdgeInsets.only(right: 8, top: 4, bottom: 2),
                child: _ProgressTrack(progress: hasLength ? progress : (_isPlaying ? 1.0 : 0.0), showThumb: hasLength),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin line showing how far through the song it is, white on a see-through white track, with a dot at the end.
class _ProgressTrack extends StatelessWidget {
  final double progress;
  final bool showThumb;

  const _ProgressTrack({required this.progress, required this.showThumb});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: LayoutBuilder(
        builder: (context, box) {
          double x = box.maxWidth * progress;
          return Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              Container(height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2))),
              Container(width: x, height: 3, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
              if (showThumb)
                Positioned(
                  left: (x - 5).clamp(0.0, box.maxWidth - 10),
                  child: Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
            ],
          );
        },
      ),
    );
  }
}
