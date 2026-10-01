import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'library_store.dart';

/// The videos on the phone, shared by the Video tab, video playlists and the
/// Hidden page, plus the "up next" queue filled by Play next / Play last.
class VideoLibrary extends ChangeNotifier {
  VideoLibrary._();
  static final VideoLibrary instance = VideoLibrary._();

  static const PermissionRequestOption _permissionOption = PermissionRequestOption(
    androidPermission: AndroidPermission(type: RequestType.video, mediaLocation: false),
  );

  List<AssetEntity> _videos = []; // Newest first
  bool isLoading = false;
  bool hasLoaded = false;
  bool noPermission = false;

  /// Videos to play after the current one, before the list carries on.
  final List<AssetEntity> upNext = [];

  List<AssetEntity> get videos => List.unmodifiable(_videos);

  AssetEntity? videoById(String id) => _videos.where((video) => video.id == id).firstOrNull;

  /// Loads (or reloads) the phone's videos, asking for permission if needed.
  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    notifyListeners();
    try {
      PermissionState permission = await PhotoManager.requestPermissionExtend(requestOption: _permissionOption);
      noPermission = !permission.hasAccess;
      if (!noPermission) {
        int count = await PhotoManager.getAssetCount(type: RequestType.video);
        List<AssetEntity> videos = count == 0
            ? []
            : await PhotoManager.getAssetListRange(start: 0, end: count, type: RequestType.video);
        videos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
        _videos = videos;
      }
    } catch (e) {
      debugPrint("Error loading videos: $e");
    }
    isLoading = false;
    hasLoaded = true;
    notifyListeners();
  }

  /// Play next: first in the up-next queue.
  void playNext(AssetEntity video) {
    upNext.removeWhere((v) => v.id == video.id);
    upNext.insert(0, video);
    notifyListeners();
  }

  /// Play last: end of the up-next queue.
  void playLast(AssetEntity video) {
    upNext.removeWhere((v) => v.id == video.id);
    upNext.add(video);
    notifyListeners();
  }

  /// Takes the next video from the up-next queue, if any.
  AssetEntity? takeUpNext() {
    if (upNext.isEmpty) return null;
    AssetEntity video = upNext.removeAt(0);
    notifyListeners();
    return video;
  }

  /// Deletes a video from the phone (Android asks the user to confirm).
  /// Returns true if it was deleted.
  Future<bool> delete(AssetEntity video) async {
    try {
      List<String> deleted = await PhotoManager.editor.deleteWithIds([video.id]);
      if (!deleted.contains(video.id)) return false;
      _videos.removeWhere((v) => v.id == video.id);
      upNext.removeWhere((v) => v.id == video.id);
      await (await LibraryStore.instance()).forgetSong(videoKey(video.id));
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error deleting video: $e");
      return false;
    }
  }
}
