import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'app_settings.dart';
import 'library_store.dart';
import 'track_info.dart';

/// The one audio player shared by the music and radio screens, so only one
/// thing plays at a time and playback continues in the background.
class PlayerService {
  PlayerService._() {
    _applySavedEqualizer();
    _countPlays();
  }
  static final PlayerService instance = PlayerService._();

  /// The equalizer (Android only); see EqualizerScreen.
  final AndroidEqualizer equalizer = AndroidEqualizer();

  late final AudioPlayer player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]));

  /// Turns the equalizer on or off as saved, and restores the saved band gains
  /// once Android makes the equalizer available (after something first plays).
  void _applySavedEqualizer() {
    AppSettings settings = AppSettings.instance;
    equalizer.setEnabled(settings.equalizerOn);
    equalizer.parameters.then((parameters) {
      List<double> gains = settings.equalizerGains;
      for (AndroidEqualizerBand band in parameters.bands) {
        if (band.index < gains.length) {
          band.setGain(gains[band.index].clamp(parameters.minDecibels, parameters.maxDecibels));
        }
      }
    });
  }

  /// Counts a song as played once it has played for 30 seconds (or half of a
  /// short one), and again each time it repeats. Feeds the smart playlists.
  void _countPlays() {
    String? counted; // The song already counted in this play
    player.positionStream.listen((position) {
      String? path = currentSongPath;
      if (path == null || !player.playing) return;
      if (position < Duration(seconds: 2)) {
        counted = null; // Just started, or repeating
        return;
      }
      Duration? length = player.duration;
      Duration needed = length != null && length < Duration(seconds: 60) ? length ~/ 2 : Duration(seconds: 30);
      if (counted != path && position >= needed) {
        counted = path;
        LibraryStore.instance().then((store) => store.recordPlay(songKey(File(path))));
      }
    });
  }

  /// Asks Android 13+ for the notification permission (see MainActivity.java),
  /// once per app run, when the app opens rather than as the first song starts,
  /// so the system prompt can't land in the middle of starting playback.
  static const MethodChannel _notifications = MethodChannel('com.msixv.com.m6player/notifications');
  bool _askedForNotifications = false;

  void askForNotifications() {
    if (_askedForNotifications || !Platform.isAndroid) return;
    _askedForNotifications = true;
    _notifications.invokeMethod('request').catchError((Object e) {
      debugPrint("Couldn't ask for the notification permission: $e");
    });
  }

  /// True while the player holds songs (as opposed to a radio stream).
  bool isLibraryActive = false;

  /// Which list of songs is loaded: [allSongsQueue], [favouritesQueue] or a
  /// playlist's id. The player's playlist is always exactly [_queuePaths].
  String? queueId;
  List<String> _queuePaths = [];

  static const String allSongsQueue = 'songs';
  static const String favouritesQueue = 'favourites';
  static const String latestQueue = 'latest';

  /// Path of the song playing now, or null when nothing (or the radio) is.
  String? get currentSongPath => isLibraryActive ? currentItem?.id : null;

  /// Plays [tracks] (the list on screen, called [id]) from [index]. The player
  /// keeps its playlist when it's already this list in this order, so tapping
  /// another song just jumps to it.
  Future<void> playQueue(String id, List<File> tracks, int index) async {
    List<String> paths = tracks.map((file) => file.path).toList();
    if (isLibraryActive && queueId == id && listEquals(paths, _queuePaths)) {
      await player.seek(Duration.zero, index: index);
    } else {
      await TrackInfoService.instance.load(tracks); // Usually already read by the Music tab
      await player.setAudioSources(tracks.map(_trackSource).toList(), initialIndex: index);
      isLibraryActive = true;
      queueId = id;
      _queuePaths = paths;
    }
    // Not awaited: play() only completes once playback pauses or stops.
    player.play();
  }

  /// Play next: puts [file] right after the current song. If no songs are
  /// playing, it starts playing on its own.
  Future<void> playNext(File file) => _enqueue(file, next: true);

  /// Play last: puts [file] at the end of what's playing. If no songs are
  /// playing, it starts playing on its own.
  Future<void> playLast(File file) => _enqueue(file, next: false);

  Future<void> _enqueue(File file, {required bool next}) async {
    if (!isLibraryActive || _queuePaths.isEmpty) {
      await playQueue('single:${file.path}', [file], 0);
      return;
    }
    await TrackInfoService.instance.load([file]);
    // Inserting a song already in the list would duplicate it; move it instead.
    int existing = _queuePaths.indexOf(file.path);
    if (existing >= 0 && existing != player.currentIndex) {
      _queuePaths.removeAt(existing);
      await player.removeAudioSourceAt(existing);
    }
    int at = next ? (player.currentIndex ?? -1) + 1 : _queuePaths.length;
    at = at.clamp(0, _queuePaths.length);
    _queuePaths.insert(at, file.path);
    await player.insertAudioSource(at, _trackSource(file));
    // The playing list no longer matches the one on screen.
    queueId = '${queueId ?? 'custom'}+';
  }

  /// A new song joined the library: add it to the end of the playlist too if
  /// "all songs" is playing. (Favourites and playlists play as they were when started.)
  Future<void> addTrack(File file) async {
    if (!isLibraryActive || queueId != allSongsQueue) return;
    await TrackInfoService.instance.load([file]);
    await player.addAudioSource(_trackSource(file));
    _queuePaths.add(file.path);
  }

  /// Queue editing from the Up next sheet. Positions are in the playlist's own
  /// order (not the shuffled one). The playing list no longer matches the one
  /// on screen afterwards.
  Future<void> moveTrack(int from, int to) async {
    if (!isLibraryActive || from == to || from < 0 || to < 0 || from >= _queuePaths.length || to >= _queuePaths.length) return;
    _queuePaths.insert(to, _queuePaths.removeAt(from));
    queueId = '${queueId ?? 'custom'}+';
    await player.moveAudioSource(from, to);
  }

  Future<void> removeTrackAt(int index) async {
    if (!isLibraryActive || index < 0 || index >= _queuePaths.length) return;
    _queuePaths.removeAt(index);
    queueId = '${queueId ?? 'custom'}+';
    await player.removeAudioSourceAt(index);
  }

  /// A song was deleted from the library: take it out of the playing
  /// playlist if it's there (whichever list that is).
  Future<void> removeTrack(File file) async {
    if (!isLibraryActive) return;
    int index = _queuePaths.indexOf(file.path);
    if (index < 0) return;
    _queuePaths.removeAt(index);
    await player.removeAudioSourceAt(index);
  }

  /// The list called [id] changed order (a new sort): if it's playing, reload
  /// it in the new order without interrupting the current song for long.
  Future<void> reorderQueue(String id, List<File> tracks) async {
    List<String> paths = tracks.map((file) => file.path).toList();
    if (!isLibraryActive || queueId != id || listEquals(paths, _queuePaths)) return;
    // Only a change of order: a list whose songs changed keeps playing as it was.
    if (paths.length != _queuePaths.length || !paths.toSet().containsAll(_queuePaths)) return;
    String? current = currentSongPath;
    int index = current == null ? 0 : paths.indexOf(current);
    if (index < 0) return;
    Duration position = player.position;
    bool wasPlaying = player.playing;
    await TrackInfoService.instance.load(tracks);
    await player.setAudioSources(tracks.map(_trackSource).toList(), initialIndex: index, initialPosition: position);
    _queuePaths = paths;
    if (wasPlaying) player.play();
  }

  /// A playlist was deleted: if it's playing it carries on as it was, but no
  /// longer matches any list.
  void forgetQueue(String id) {
    if (queueId == id) queueId = null;
  }

  /// Replaces whatever is playing with a radio stream.
  Future<void> playStream(String url, String title) async {
    isLibraryActive = false;
    queueId = null;
    _queuePaths = [];
    await player.setSpeed(1.0); // A live stream can't be sped up
    await player.setAudioSource(AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(id: url, title: title, album: 'Radio', extras: {'radio': true}),
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

  /// True while a video is playing (set by the video player), so the logo
  /// can animate for videos as well as music.
  final ValueNotifier<bool> videoPlaying = ValueNotifier(false);

  /// Sleep timer: when playback will pause, or null when it's off.
  final ValueNotifier<DateTime?> sleepAt = ValueNotifier(null);

  /// Sleep timer set to pause at the end of the current song.
  final ValueNotifier<bool> sleepAtEndOfSong = ValueNotifier(false);

  Timer? _sleepTimer;
  final List<StreamSubscription> _endOfSongWatch = [];

  /// Pauses playback after [delay]. Replaces any timer already set.
  void setSleepTimer(Duration delay) {
    cancelSleepTimer();
    sleepAt.value = DateTime.now().add(delay);
    _sleepTimer = Timer(delay, _sleepNow);
  }

  /// Pauses when the current song (or radio, never) ends: on the next
  /// automatic move to another song, or when the playlist finishes.
  void sleepAfterCurrentSong() {
    cancelSleepTimer();
    sleepAtEndOfSong.value = true;
    _endOfSongWatch.addAll([
      player.positionDiscontinuityStream
          .where((event) => event.reason == PositionDiscontinuityReason.autoAdvance)
          .listen((_) => _sleepNow()),
      player.processingStateStream
          .where((state) => state == ProcessingState.completed)
          .listen((_) => _sleepNow()),
    ]);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    for (final watch in _endOfSongWatch) {
      watch.cancel();
    }
    _endOfSongWatch.clear();
    sleepAt.value = null;
    sleepAtEndOfSong.value = false;
  }

  void _sleepNow() {
    player.pause();
    cancelSleepTimer();
  }

  /// A song for the playlist, with its tags and cover (shown on the lock
  /// screen and notification too). Tags must already be loaded by TrackInfoService.
  AudioSource _trackSource(File file) {
    TrackInfo info = TrackInfoService.instance.infoFor(file);
    String? cover = info.coverPath;
    return AudioSource.file(
      file.path,
      tag: MediaItem(
        id: file.path,
        title: info.title,
        artist: info.artist,
        album: info.album,
        artUri: cover == null ? null : Uri.file(cover),
      ),
    );
  }
}

/// True for a radio station, false for a song.
bool isRadioItem(MediaItem? item) => item?.extras?['radio'] == true;

/// Line under the title: the artist (and album) for a song, "Radio" for a station.
String itemSubtitle(MediaItem item) => isRadioItem(item) ? 'Radio' : songSubtitle(item.artist, item.album);

/// "Artist · Album", whichever of the two is known, or "Unknown artist".
String songSubtitle(String? artist, String? album) {
  if (artist != null && album != null) return '$artist · $album';
  return artist ?? album ?? 'Unknown artist';
}

/// Display name for a track: its file name without the extension.
String trackTitle(File file) {
  String name = file.uri.pathSegments.last;
  int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
