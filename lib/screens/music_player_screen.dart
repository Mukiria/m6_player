import 'package:flutter/material.dart';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import '../utils/file_helper.dart';
import 'radio_screen.dart';

class MusicPlayerScreen extends StatefulWidget {
  @override
  _MusicPlayerScreenState createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<File> _mp3Files = [];
  File? _currentlyPlayingFile;
  bool _isPlaying = false;
  bool _isShuffling = false;
  bool _isRepeating = false;
  double _volume = 1.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
    });

    _audioPlayer.positionStream.listen((position) {
      setState(() => _currentPosition = position);
    });

    _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        setState(() => _totalDuration = duration);
      }
    });
  }

  Future<void> addMp3File() async {
    File? file = await pickMp3File();
    if (file != null) {
      setState(() => _mp3Files.add(file));
    }
  }

  Future<void> togglePlayPause(File file) async {
    try {
      if (_currentlyPlayingFile == file && _isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_currentlyPlayingFile != null) await _audioPlayer.stop();
        await _audioPlayer.setFilePath(file.path);
        await _audioPlayer.play();
        setState(() => _currentlyPlayingFile = file);
      }
    } catch (e) {
      print("Error playing file: $e");
    }
  }

  void seekTo(Duration position) {
    _audioPlayer.seek(position);
  }

  String formatDuration(Duration duration) {
    String minutes = duration.inMinutes.toString().padLeft(2, '0');
    String seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void _changeVolume(double delta) {
    setState(() {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      _audioPlayer.setVolume(_volume);
    });
  }

  void _toggleShuffle() {
    setState(() => _isShuffling = !_isShuffling);
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _toggleRepeat() {
    setState(() => _isRepeating = !_isRepeating);
  }

  void deleteMp3File(File file) {
    deleteFile(file.path);
    setState(() {
      _mp3Files.remove(file);
    });

    if (_currentlyPlayingFile == file) {
      stopPlayback();
    }
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
    });
  }

  // ✅ Fixed Previous Song Function
  Future<void> playPreviousSong() async {
    if (_mp3Files.isEmpty || _currentlyPlayingFile == null) return;

    int currentIndex = _mp3Files.indexOf(_currentlyPlayingFile!);
    if (currentIndex > 0) {
      togglePlayPause(_mp3Files[currentIndex - 1]);
    }
  }

  // ✅ Fixed Next Song Function
  Future<void> playNextSong() async {
    if (_mp3Files.isEmpty || _currentlyPlayingFile == null) return;

    int currentIndex = _mp3Files.indexOf(_currentlyPlayingFile!);
    if (currentIndex < _mp3Files.length - 1) {
      togglePlayPause(_mp3Files[currentIndex + 1]);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
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
                    Navigator.push(context, MaterialPageRoute(builder: (context) => RadioScreen()));
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
                  title: Text(file.path.split('/').last, style: TextStyle(color: Colors.white)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          (_currentlyPlayingFile == file && _isPlaying)
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () => togglePlayPause(file),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () => deleteMp3File(file),
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
                color: Colors.black.withOpacity(0.8),
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
                        value: _currentPosition.inSeconds.toDouble(),
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
                        onPressed: () => playNextSong,
                      ),
                      IconButton(icon: Icon(Icons.repeat, color: Colors.white), onPressed: _toggleRepeat),
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
