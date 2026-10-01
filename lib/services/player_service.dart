import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// The one audio player shared by the music and radio screens, so only one
/// thing plays at a time and playback continues in the background.
class PlayerService {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  final AudioPlayer player = AudioPlayer();

  /// True while the player holds the music library as its playlist
  /// (as opposed to a radio stream).
  bool isLibraryActive = false;

  /// Loads the library as the playlist (if it isn't already) and plays [index].
  Future<void> playLibrary(List<File> tracks, int index) async {
    if (!isLibraryActive) {
      await player.setAudioSources(
        tracks.map(_trackSource).toList(),
        initialIndex: index,
      );
      isLibraryActive = true;
    } else {
      await player.seek(Duration.zero, index: index);
    }
    // Not awaited: play() only completes once playback pauses or stops.
    player.play();
  }

  Future<void> addTrack(File file) async {
    if (isLibraryActive) await player.addAudioSource(_trackSource(file));
  }

  Future<void> removeTrack(int index) async {
    if (isLibraryActive) await player.removeAudioSourceAt(index);
  }

  /// Replaces whatever is playing with a radio stream.
  Future<void> playStream(String url, String title) async {
    isLibraryActive = false;
    await player.setAudioSource(AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(id: url, title: title, album: 'Radio'),
    ));
    player.play();
  }

  Future<void> stop() => player.stop();

  /// Play button. After the last song has finished, starts again from the first.
  Future<void> resume() async {
    if (player.processingState == ProcessingState.completed && isLibraryActive) {
      await player.seek(Duration.zero, index: player.effectiveIndices.first);
    }
    player.play();
  }

  /// Next button. After the last song it wraps round to the first (in shuffle
  /// order when shuffle is on), and a finished playlist starts playing again.
  Future<void> next() async {
    if (!isLibraryActive || player.sequence.isEmpty) return;
    bool finished = player.processingState == ProcessingState.completed;
    if (player.hasNext) {
      await player.seekToNext();
    } else {
      await player.seek(Duration.zero, index: player.effectiveIndices.first);
    }
    if (finished) player.play();
  }

  /// Previous button: restarts the song if it's more than 3 seconds in,
  /// otherwise goes to the previous song (from the first, wraps to the last).
  Future<void> previous() async {
    if (!isLibraryActive || player.sequence.isEmpty) return;
    if (player.position > Duration(seconds: 3) || player.sequence.length == 1) {
      await player.seek(Duration.zero);
    } else if (player.hasPrevious) {
      await player.seekToPrevious();
    } else {
      await player.seek(Duration.zero, index: player.effectiveIndices.last);
    }
  }

  /// What is playing now (a song or a station), for the mini player and the
  /// Now Playing screen. Null when nothing has been loaded yet.
  Stream<MediaItem?> get currentItemStream =>
      player.sequenceStateStream.map((state) => state.currentSource?.tag as MediaItem?);

  MediaItem? get currentItem => player.sequenceState.currentSource?.tag as MediaItem?;

  AudioSource _trackSource(File file) => AudioSource.file(
        file.path,
        tag: MediaItem(id: file.path, title: trackTitle(file), album: 'My music'),
      );
}

/// Display name for a track: its file name without the extension.
String trackTitle(File file) {
  String name = file.uri.pathSegments.last;
  int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
