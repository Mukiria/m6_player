import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'car_browser.dart';
import 'player_service.dart';

/// Connects the app's player to the system media controls: the notification
/// panel, the lock screen and headset buttons.
///
/// Notification buttons: the m6 mark (opens the app), then previous,
/// play/pause (switching with the state) and next for songs, or play/pause for
/// radio, plus a close (✕) button that stops playback and removes the notification.
class M6AudioHandler extends BaseAudioHandler with SeekHandler {
  final PlayerService _service;
  AudioPlayer get _player => _service.player;

  /// The close (✕) and m6 mark buttons' action names.
  static const String closeAction = 'close';
  static const String openAppAction = 'open_app';

  /// Opens the app from the m6 mark button (see MainActivity.java).
  static const MethodChannel _app = MethodChannel('com.msixv.com.m6player/notifications');

  static final MediaControl _logo = MediaControl.custom(
    androidIcon: 'drawable/ic_notification_logo',
    label: 'Open M6 Player',
    name: openAppAction,
  );

  static final MediaControl _close = MediaControl.custom(
    androidIcon: 'drawable/ic_notification_close',
    label: 'Close',
    name: closeAction,
  );

  M6AudioHandler(this._service) {
    _player.playbackEventStream.listen((_) => _broadcastState(), onError: (Object e, StackTrace s) {
      _broadcastState();
    });
    _player.playingStream.listen((_) => _broadcastState());
    // What's playing, with its length once known (for the notification's seek bar).
    _service.currentItemStream.listen((item) => _publishItem(item, _player.duration));
    _player.durationStream.listen((duration) => _publishItem(_service.currentItem, duration));
  }

  void _publishItem(MediaItem? item, Duration? duration) {
    if (item == null) return;
    mediaItem.add(isRadioItem(item) ? item : item.copyWith(duration: duration));
  }

  /// Sends the player's state and the right buttons to the system.
  void _broadcastState() {
    bool isRadio = isRadioItem(_service.currentItem);
    bool playing = _player.playing;
    MediaControl playPause = playing ? MediaControl.pause : MediaControl.play;
    List<MediaControl> controls = isRadio
        ? [_logo, playPause, _close]
        : [_logo, MediaControl.skipToPrevious, playPause, MediaControl.skipToNext, _close];
    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      systemActions: {
        if (!isRadio) ...{MediaAction.seek, MediaAction.skipToPrevious, MediaAction.skipToNext},
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.stop,
      },
      // Buttons shown when the notification is collapsed (Android 12 and older;
      // Android 13+ chooses for itself): previous, play/pause, next.
      androidCompactActionIndices: isRadio ? [1] : [1, 2, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    ));
  }

  @override
  Future<void> play() => _service.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  // Same rules as the app's buttons: next wraps to the first song, previous
  // restarts a song that's more than 3 seconds in.
  @override
  Future<void> skipToNext() => _service.next();

  @override
  Future<void> skipToPrevious() => _service.previous();

  // Android Auto: the car's browse menu and voice commands (see CarBrowser).
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) =>
      CarBrowser.children(parentMediaId, options);

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) => CarBrowser.search(query);

  @override
  Future<MediaItem?> getMediaItem(String mediaId) => CarBrowser.item(mediaId);

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) => CarBrowser.play(mediaId);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) => CarBrowser.playSearch(query);

  /// Stop (also the close button): stops playback and removes the notification.
  @override
  Future<void> stop() async {
    await _service.stop();
    await super.stop();
  }

  /// The app was swiped away from the recent apps: stop playback and remove
  /// the notification, so swiping away really closes the app.
  @override
  Future<void> onTaskRemoved() => stop();

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == closeAction) await stop();
    if (name == openAppAction) {
      try {
        await _app.invokeMethod('openApp');
      } catch (_) {
        // Android may refuse to open an app from the background; nothing else to do.
      }
    }
  }
}
