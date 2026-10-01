import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/player_service.dart';
import '../utils/file_helper.dart';
import '../widgets/app_logo.dart';

/// The Music tab: the user's song library. Tap a song to play it; the playback
/// controls live in the mini player and the Now Playing screen.
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

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _audioPlayer.playerStateStream.listen((state) {
        setState(() => _isPlaying = state.playing);
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

  bool _isImporting = false;

  /// "Add" button: choose songs, or a whole folder.
  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.audio_file_outlined),
              title: Text("Choose songs"),
              subtitle: Text("Pick one or more MP3s"),
              onTap: () {
                Navigator.pop(context);
                _addSongs();
              },
            ),
            ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text("Add a folder"),
              subtitle: Text("Adds every MP3 in it, including subfolders"),
              onTap: () {
                Navigator.pop(context);
                _addFolder();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSongs() async {
    try {
      await _import(await pickMp3Files());
    } catch (e) {
      debugPrint("Error picking files: $e");
    }
  }

  Future<void> _addFolder() async {
    try {
      Directory? folder = await pickFolder();
      if (folder == null) return;
      if (!await requestAudioPermission()) {
        _showMessage("m6 player needs permission to read your music to add a folder.");
        return;
      }
      List<File> songs = await findMp3s(folder);
      if (songs.isEmpty) {
        _showMessage("No MP3s found in that folder.");
        return;
      }
      await _import(songs);
    } catch (e) {
      debugPrint("Error adding folder: $e");
      _showMessage("Couldn't read that folder. Try choosing the songs instead.");
    }
  }

  /// Copies [picked] songs into the library (skipping ones already there) and
  /// adds them to the end of the playlist.
  Future<void> _import(List<File> picked) async {
    if (picked.isEmpty || _libraryDir == null) return;
    setState(() => _isImporting = true);
    int added = 0, skipped = 0;
    for (File source in picked) {
      try {
        if (isInLibrary(source, _mp3Files)) {
          skipped++;
          continue;
        }
        File file = await importToLibrary(source, _libraryDir!);
        await _service.addTrack(file);
        if (!mounted) return;
        setState(() => _mp3Files.add(file));
        added++;
      } catch (e) {
        debugPrint("Error adding ${source.path}: $e");
      }
    }
    if (!mounted) return;
    setState(() => _isImporting = false);
    if (picked.length > 1 || skipped > 0) {
      String message = "Added $added ${added == 1 ? "song" : "songs"}";
      if (skipped > 0) message += " ($skipped already in your library)";
      _showMessage(message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Tapping a song plays it; tapping the current song pauses or resumes it.
  Future<void> togglePlayPause(int index) async {
    try {
      if (_currentIndex == index && _isPlaying) {
        await _audioPlayer.pause();
      } else if (_currentIndex == index) {
        await _service.resume();
      } else {
        await _service.playLibrary(_mp3Files, index);
      }
    } catch (e) {
      debugPrint("Error playing file: $e");
    }
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
    ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: AppLogo(),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: "Add songs",
            icon: Icon(Icons.add),
            onPressed: _isImporting ? null : _showAddOptions,
          ),
        ],
        bottom: _isImporting
            ? PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: _mp3Files.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.library_music_outlined, size: 64, color: colors.onSurfaceVariant),
                  SizedBox(height: 16),
                  Text("No songs yet", style: TextStyle(fontSize: 18)),
                  SizedBox(height: 4),
                  Text("Add MP3s or a music folder from your phone.",
                      style: TextStyle(color: colors.onSurfaceVariant)),
                  SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isImporting ? null : _showAddOptions,
                    icon: Icon(Icons.add),
                    label: Text("Add songs"),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text("Songs (${_mp3Files.length})",
                      style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _mp3Files.length,
                    itemBuilder: (context, index) => _songTile(index, colors),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _songTile(int index, ColorScheme colors) {
    File file = _mp3Files[index];
    bool isCurrent = _currentIndex == index;
    return ListTile(
      contentPadding: EdgeInsets.only(left: 16, right: 4),
      leading: isCurrent
          ? Icon(_isPlaying ? Icons.graphic_eq : Icons.pause, color: colors.primary)
          : null,
      minLeadingWidth: 24,
      title: Text(
        trackTitle(file),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? colors.primary : null,
          fontWeight: isCurrent ? FontWeight.w600 : null,
        ),
      ),
      subtitle: Text(_fileSize(file), style: TextStyle(color: colors.onSurfaceVariant)),
      onTap: () => togglePlayPause(index),
      trailing: PopupMenuButton<String>(
        tooltip: "More",
        icon: Icon(Icons.more_vert),
        onSelected: (action) {
          if (action == "play") togglePlayPause(index);
          if (action == "remove") deleteMp3File(index);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: "play",
            child: Text(isCurrent && _isPlaying ? "Pause" : "Play"),
          ),
          PopupMenuItem(value: "remove", child: Text("Remove")),
        ],
      ),
    );
  }

  /// File size such as "4.2 MB", shown under the song title.
  String _fileSize(File file) {
    try {
      return "${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB";
    } catch (_) {
      return "";
    }
  }
}
