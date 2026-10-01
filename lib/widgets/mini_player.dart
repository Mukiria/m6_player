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

    ColorScheme colors = Theme.of(context).colorScheme;
    bool isRadio = isRadioItem(item);
    // Radio streams have no length, so the ring just shows "playing" in full.
    double progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : (_isPlaying ? 1.0 : 0.0);

    return Material(
      color: colors.surfaceContainerHigh,
      child: InkWell(
        onTap: _openNowPlaying,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Artwork(size: 44, isRadio: isRadio, round: true, coverPath: item.artUri?.toFilePath()),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    Text(itemSubtitle(item), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2,
                      color: colors.primary,
                      backgroundColor: colors.outlineVariant,
                    ),
                    IconButton(
                      tooltip: _isPlaying ? 'Pause' : 'Play',
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      onPressed: () => _isPlaying ? _audioPlayer.pause() : _service.resume(),
                    ),
                  ],
                ),
              ),
              if (!isRadio)
                IconButton(
                  tooltip: 'Next',
                  icon: Icon(Icons.skip_next),
                  onPressed: _service.next,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
