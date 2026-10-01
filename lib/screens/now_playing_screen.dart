import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../services/library_store.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/artwork.dart';
import '../widgets/playlist_picker.dart';

/// Full-screen player: artwork, seek bar and all the playback controls.
/// Always dark, whatever the phone's theme, so the artwork stands out.
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  final PlayerService _service = PlayerService.instance;
  AudioPlayer get _audioPlayer => _service.player;
  final List<StreamSubscription> _subscriptions = [];

  MediaItem? _item;
  bool _isPlaying = false;
  bool _isShuffling = false;
  LoopMode _loopMode = LoopMode.off;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _dragPosition; // While the user drags the seek bar
  LibraryStore? _store;
  Timer? _clock; // Redraws the sleep timer's minutes left

  @override
  void initState() {
    super.initState();
    _item = _service.currentItem;
    _isPlaying = _audioPlayer.playing;
    _isShuffling = _audioPlayer.shuffleModeEnabled;
    _loopMode = _audioPlayer.loopMode;
    _subscriptions.addAll([
      _service.currentItemStream.listen((item) {
        // Nothing left to show (e.g. the last song was removed): close.
        if (item == null && mounted) Navigator.of(context).maybePop();
        setState(() => _item = item);
      }),
      _audioPlayer.playerStateStream.listen((state) => setState(() => _isPlaying = state.playing)),
      _audioPlayer.positionStream.listen((position) => setState(() => _position = position)),
      _audioPlayer.durationStream.listen((duration) => setState(() => _duration = duration ?? Duration.zero)),
      _audioPlayer.shuffleModeEnabledStream.listen((enabled) => setState(() => _isShuffling = enabled)),
      _audioPlayer.loopModeStream.listen((mode) => setState(() => _loopMode = mode)),
    ]);
    _service.sleepAt.addListener(_onChanged);
    _service.sleepAtEndOfSong.addListener(_onChanged);
    _clock = Timer.periodic(Duration(seconds: 15), (_) => _onChanged());
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onChanged);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _service.sleepAt.removeListener(_onChanged);
    _service.sleepAtEndOfSong.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    _clock?.cancel();
    super.dispose();
  }

  bool get _isFavourite {
    File? song = _currentSong;
    return song != null && (_store?.isFavourite(songKey(song)) ?? false);
  }

  /// The song playing now as a library file (null for radio).
  File? get _currentSong {
    String? path = _service.currentSongPath;
    return path == null ? null : File(path);
  }

  /// Sleep timer label: minutes left, "End of song", or null when off.
  String? get _sleepLabel {
    if (_service.sleepAtEndOfSong.value) return "End of song";
    DateTime? at = _service.sleepAt.value;
    if (at == null) return null;
    int minutes = (at.difference(DateTime.now()).inSeconds / 60).ceil();
    return "$minutes min";
  }

  void _showSleepTimer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: brandNavyRaised,
      builder: (context) {
        TextStyle style = TextStyle(color: Colors.white);
        Widget option(String label, VoidCallback onTap) => ListTile(
              title: Text(label, style: style),
              onTap: () {
                onTap();
                Navigator.of(context).pop();
              },
            );
        bool isRadio = isRadioItem(_item);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text("Sleep timer", style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w600))),
              if (_sleepLabel != null) option("Turn off", _service.cancelSleepTimer),
              for (int minutes in [15, 30, 45, 60, 90])
                option("$minutes minutes", () => _service.setSleepTimer(Duration(minutes: minutes))),
              if (!isRadio) option("End of this song", _service.sleepAfterCurrentSong),
            ],
          ),
        );
      },
    );
  }


  void _toggleShuffle() => _audioPlayer.setShuffleModeEnabled(!_isShuffling);

  /// Cycles repeat: off -> all -> one -> off.
  void _toggleRepeat() {
    const modes = [LoopMode.off, LoopMode.all, LoopMode.one];
    _audioPlayer.setLoopMode(modes[(modes.indexOf(_loopMode) + 1) % modes.length]);
  }

  void _showQueue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: brandNavyRaised,
      builder: (context) => _QueueSheet(player: _audioPlayer),
    );
  }

  @override
  Widget build(BuildContext context) {
    MediaItem? item = _item;
    bool isRadio = isRadioItem(item);
    Color accent = brandBlueLight;
    Color muted = Colors.white70;

    // Position can briefly exceed duration at the end of a track.
    Duration shown = _dragPosition ?? (_position > _duration ? _duration : _position);

    return Theme(
      data: darkTheme(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [brandNavyRaised, brandNavy, Colors.black],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Top bar: close and the up-next list
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        icon: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Spacer(),
                      if (!isRadio)
                        IconButton(
                          tooltip: 'Up next',
                          icon: Icon(Icons.queue_music, color: Colors.white),
                          onPressed: _showQueue,
                        ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    item?.title ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(item == null ? '' : itemSubtitle(item),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 14)),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Artwork(
                          size: (constraints.biggest.shortestSide * 0.85).clamp(120.0, 320.0),
                          isRadio: isRadio,
                          coverPath: item?.artUri?.toFilePath(),
                        ),
                      ),
                    ),
                  ),

                  // Favourite, add to playlist (songs only) and the sleep timer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (_currentSong != null) ...[
                        IconButton(
                          tooltip: _isFavourite ? "Remove from favourites" : "Add to favourites",
                          icon: Icon(_isFavourite ? Icons.favorite : Icons.favorite_border,
                              color: _isFavourite ? accent : Colors.white),
                          onPressed: () => _store?.toggleFavourite(songKey(_currentSong!)),
                        ),
                        IconButton(
                          tooltip: "Add to playlist",
                          icon: Icon(Icons.playlist_add, color: Colors.white),
                          onPressed: () => showAddToPlaylist(context, _currentSong!),
                        ),
                      ],
                      TextButton.icon(
                        onPressed: _showSleepTimer,
                        icon: Icon(Icons.bedtime_outlined, color: _sleepLabel == null ? Colors.white : accent),
                        label: Text(_sleepLabel ?? "Sleep",
                            style: TextStyle(color: _sleepLabel == null ? Colors.white : accent)),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),

                  // Seek bar (songs only: a live stream has no length)
                  if (!isRadio) ...[
                    Slider(
                      value: shown.inMilliseconds.toDouble(),
                      max: _duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                      activeColor: accent,
                      inactiveColor: Colors.white24,
                      onChanged: (value) => setState(() => _dragPosition = Duration(milliseconds: value.round())),
                      onChangeEnd: (value) {
                        _audioPlayer.seek(Duration(milliseconds: value.round()));
                        setState(() => _dragPosition = null);
                      },
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatDuration(shown), style: TextStyle(color: muted, fontSize: 12)),
                          Text(formatDuration(_duration), style: TextStyle(color: muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ] else
                    Text('LIVE', style: TextStyle(color: accent, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  SizedBox(height: 16),

                  // Controls: shuffle, previous, play/pause, next, repeat
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Shuffle',
                        icon: Icon(Icons.shuffle, color: _isShuffling ? accent : Colors.white),
                        onPressed: isRadio ? null : _toggleShuffle,
                      ),
                      IconButton(
                        tooltip: 'Previous',
                        iconSize: 36,
                        icon: Icon(Icons.skip_previous, color: Colors.white),
                        onPressed: isRadio ? null : _service.previous,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: IconButton(
                          tooltip: _isPlaying ? 'Pause' : 'Play',
                          iconSize: 44,
                          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                          onPressed: () => _isPlaying ? _audioPlayer.pause() : _service.resume(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        iconSize: 36,
                        icon: Icon(Icons.skip_next, color: Colors.white),
                        onPressed: isRadio ? null : _service.next,
                      ),
                      IconButton(
                        tooltip: 'Repeat',
                        icon: Icon(
                          _loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                          color: _loopMode == LoopMode.off ? Colors.white : accent,
                        ),
                        onPressed: isRadio ? null : _toggleRepeat,
                      ),
                    ],
                  ),
                  SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The playlist in play order (shuffled order when shuffle is on); tap a song to jump to it.
class _QueueSheet extends StatelessWidget {
  final AudioPlayer player;

  const _QueueSheet({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState>(
      stream: player.sequenceStateStream,
      builder: (context, snapshot) {
        SequenceState state = snapshot.data ?? player.sequenceState;
        List<IndexedAudioSource> sequence = state.sequence;
        List<int> order = state.shuffleModeEnabled
            ? state.shuffleIndices
            : List.generate(sequence.length, (index) => index);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text('Up next', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: order.length,
                  itemBuilder: (context, position) {
                    int index = order[position];
                    MediaItem? item = sequence[index].tag as MediaItem?;
                    bool isCurrent = index == state.currentIndex;
                    return ListTile(
                      leading: isCurrent ? Icon(Icons.graphic_eq, color: brandBlueLight) : null,
                      title: Text(
                        item?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: isCurrent ? brandBlueLight : Colors.white),
                      ),
                      subtitle: item == null
                          ? null
                          : Text(itemSubtitle(item),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white60)),
                      onTap: () {
                        player.seek(Duration.zero, index: index);
                        player.play();
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
