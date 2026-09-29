import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/player_service.dart';
import '../utils/file_helper.dart';
import '../utils/format.dart';
import 'radio_screen.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final PlayerService _service = PlayerService.instance;
  AudioPlayer get _audioPlayer => _service.player;
  final List<StreamSubscription> _subscriptions = [];

  Directory? _libraryDir;
  List<File> _mp3Files = [];
  int? _currentIndex; // Index into _mp3Files of the current track, if any
  bool _isPlaying = false;
  bool _isShuffling = false;
  LoopMode _loopMode = LoopMode.off;
  double _volume = 1.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _isShuffling = _audioPlayer.shuffleModeEnabled;
    _loopMode = _audioPlayer.loopMode;
    _volume = _audioPlayer.volume;

    _subscriptions.addAll([
      _audioPlayer.playerStateStream.listen((state) {
        setState(() => _isPlaying = state.playing);
      }),
      _audioPlayer.positionStream.listen((position) {
        setState(() => _currentPosition = position);
      }),
      _audioPlayer.durationStream.listen((duration) {
        setState(() => _totalDuration = duration ?? Duration.zero);
      }),
      _audioPlayer.currentIndexStream.listen((index) {
        setState(() => _currentIndex = _service.isLibraryActive ? index : null);
      }),
    ]);
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      Directory dir = await libraryDirectory();
      List<File> files = await loadLibrary(dir);
      if (!mounted) return;
      setState(() {
        _libraryDir = dir;
        _mp3Files = files;
      });
    } catch (e) {
      debugPrint("Error loading library: $e");
    }
  }

  Future<void> addMp3File() async {
    File? picked = await pickMp3File();
    if (picked == null || _libraryDir == null) return;
    try {
      File file = await importToLibrary(picked, _libraryDir!);
      await _service.addTrack(file);
      if (!mounted) return;
      setState(() => _mp3Files.add(file));
    } catch (e) {
      debugPrint("Error adding file: $e");
    }
  }

  /// Play/pause button on a track in the list.
  Future<void> togglePlayPause(int index) async {
    try {
      if (_currentIndex == index && _isPlaying) {
        await _audioPlayer.pause();
      } else if (_currentIndex == index) {
        _audioPlayer.play();
      } else {
        await _service.playLibrary(_mp3Files, index);
      }
    } catch (e) {
      debugPrint("Error playing file: $e");
    }
  }

  void seekTo(Duration position) {
    _audioPlayer.seek(position);
  }

  void _changeVolume(double delta) {
    setState(() {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      _audioPlayer.setVolume(_volume);
    });
  }

  void _toggleShuffle() {
    setState(() => _isShuffling = !_isShuffling);
    _audioPlayer.setShuffleModeEnabled(_isShuffling);
  }

  /// Main play/pause button. Starts the library if nothing is loaded yet.
  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else if (_currentIndex == null && _mp3Files.isNotEmpty) {
      await togglePlayPause(0);
    } else if (_audioPlayer.audioSources.isNotEmpty) {
      _audioPlayer.play();
    }
  }

  /// Cycles repeat: off -> all -> one -> off.
  void _toggleRepeat() {
    const modes = [LoopMode.off, LoopMode.all, LoopMode.one];
    setState(() => _loopMode = modes[(modes.indexOf(_loopMode) + 1) % modes.length]);
    _audioPlayer.setLoopMode(_loopMode);
  }

  Future<void> deleteMp3File(int index) async {
    File file = _mp3Files[index];
    bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Remove song?"),
            content: Text(
                "Remove \"${trackTitle(file)}\" from m6 player? The original file on your device is not affected."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Remove")),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    await _service.removeTrack(index);
    await removeFromLibrary(file);
    if (!mounted) return;
    setState(() {
      _mp3Files.removeAt(index);
      if (_mp3Files.isEmpty) _currentIndex = null;
    });
  }

  Future<void> playPreviousSong() async {
    if (_service.isLibraryActive) await _audioPlayer.seekToPrevious();
  }

  Future<void> playNextSong() async {
    if (_service.isLibraryActive) await _audioPlayer.seekToNext();
  }

  @override
  void dispose() {
    // The player is shared and keeps playing in the background; just stop listening.
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ✅ Background Image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/splash-screen.jpg"),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // ✅ Top Bar (Logo & Title)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            decoration: BoxDecoration(
              color: Color(0xFFF1552C),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset("assets/logo.png", height: 60),
                SizedBox(width: 10),
                Text("m6 player",
                    style: TextStyle(
                        fontFamily: "Code",
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
          ),

          // ✅ Floating Buttons (Add Song & Radio)
          Positioned(
            top: 120,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  onPressed: addMp3File,
                  backgroundColor: Colors.black,
                  child: Icon(Icons.add, color: Colors.white),
                ),
                SizedBox(width: 20),
                FloatingActionButton.extended(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const RadioScreen()));
                  },
                  backgroundColor: Colors.black,
                  icon: Icon(Icons.radio, color: Colors.white),
                  label: Text("Radio", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),

          Positioned(
            top: 180,
            left: 0,
            right: 0,
            bottom: 150,
            child: _mp3Files.isEmpty
                ? Center(
              child: Text(
                "No MP3 files found. Tap + to add.",
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            )
                : ListView.builder(
              itemCount: _mp3Files.length,
              itemBuilder: (context, index) {
                File file = _mp3Files[index];
                return ListTile(
                  title: Text(trackTitle(file), style: TextStyle(color: Colors.white)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          (_currentIndex == index && _isPlaying)
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () => togglePlayPause(index),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () => deleteMp3File(index),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ✅ Bottom Bar with Seek Bar
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.only(bottom: 10),
              width: MediaQuery.of(context).size.width * 0.9,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(15),
              ),
              padding: EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ Seek Bar
                  Column(
                    children: [
                      Slider(
                        // Position can briefly exceed duration at the end of a track
                        value: _currentPosition.inSeconds
                            .clamp(0, _totalDuration.inSeconds)
                            .toDouble(),
                        min: 0,
                        max: _totalDuration.inSeconds.toDouble(),
                        onChanged: (value) => seekTo(Duration(seconds: value.toInt())),
                        activeColor: Colors.white,
                        inactiveColor: Colors.grey,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDuration(_currentPosition),
                            style: TextStyle(color: Colors.white),
                          ),
                          Text(
                            formatDuration(_totalDuration),
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ✅ Volume Up Button (Above Play/Pause)
                  IconButton(
                    icon: Icon(Icons.volume_up, color: Colors.white, size: 30),
                    onPressed: () => _changeVolume(0.1),
                  ),

                  // ✅ Bottom Control Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: _isShuffling ? Colors.orange : Colors.white,
                          size: 30,
                        ),
                        onPressed: _toggleShuffle,
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_previous, color: Colors.white, size: 30),
                        onPressed: playPreviousSong,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 40,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next, color: Colors.white, size: 30),
                        onPressed: playNextSong,
                      ),
                      IconButton(
                        icon: Icon(
                          _loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                          color: _loopMode == LoopMode.off ? Colors.white : Colors.orange,
                          size: 30,
                        ),
                        onPressed: _toggleRepeat,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.volume_down, color: Colors.white, size: 30),
                    onPressed: () => _changeVolume(-0.1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
