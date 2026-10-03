import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/library_store.dart';
import '../services/video_library.dart';
import 'video_list.dart';

/// Rebuilds when videos load or change, or are hidden.
Listenable _changes() => Listenable.merge([VideoLibrary.instance, ?LibraryStore.loaded]);

/// The phone's videos (not hidden), newest first, grouped by the folder they're in.
Map<String, List<AssetEntity>> videoFolders() {
  Map<String, List<AssetEntity>> folders = {};
  for (AssetEntity video in VideoLibrary.instance.videos) {
    if (LibraryStore.loaded?.isHidden(videoKey(video.id)) ?? false) continue;
    folders.putIfAbsent(video.relativePath ?? '', () => []).add(video);
  }
  return folders;
}

/// A folder's own name: the last part of its path ("Movies/Trips/" is "Trips").
String folderName(String path) {
  List<String> parts = path.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? "Other videos" : parts.last;
}

/// The Video tab's Folders page: one row per folder, A to Z.
class VideoFolders extends StatelessWidget {
  const VideoFolders({super.key});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _changes(),
      builder: (context, _) {
        Map<String, List<AssetEntity>> folders = videoFolders();
        List<String> paths = folders.keys.toList()
          ..sort((a, b) => folderName(a).toLowerCase().compareTo(folderName(b).toLowerCase()));
        if (paths.isEmpty) {
          return Center(child: Text("No videos on this phone yet.", style: TextStyle(color: colors.onSurfaceVariant)));
        }
        return ListView.builder(
          padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom), // Clear of the bottom nav
          itemCount: paths.length,
          itemBuilder: (context, index) {
            String path = paths[index];
            List<AssetEntity> videos = folders[path]!;
            return ListTile(
              leading: VideoThumbnail(video: videos.first, width: 80, height: 48),
              title: Text(folderName(path), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                "${videos.length == 1 ? "1 video" : "${videos.length} videos"}${path.isEmpty ? "" : " · $path"}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => FolderScreen(path: path))),
            );
          },
        );
      },
    );
  }
}

/// The videos in one folder.
class FolderScreen extends StatelessWidget {
  final String path;

  const FolderScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(folderName(path))),
      body: ListenableBuilder(
        listenable: _changes(),
        builder: (context, _) {
          List<AssetEntity> videos = videoFolders()[path] ?? [];
          if (videos.isEmpty) return Center(child: Text("No videos"));
          return VideoList(videos: videos, header: "${videos.length} ${videos.length == 1 ? "video" : "videos"}");
        },
      ),
    );
  }
}
