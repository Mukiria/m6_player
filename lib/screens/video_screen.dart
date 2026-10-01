import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/library_store.dart';
import '../services/video_library.dart';
import '../widgets/app_logo.dart';
import '../widgets/item_actions.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/video_list.dart';
import 'hidden_screen.dart';
import 'playlist_screen.dart';
import 'transfer_screen.dart';

/// The Video tab: Videos (every video on the phone, newest first), Favourites,
/// Latest and Playlists. Hidden videos are left out of every list, filtered-out
/// ones out of Videos. Nothing is copied; videos play where they are.
class VideoScreen extends StatefulWidget {
  /// True while the Video tab is the one on screen.
  final bool isVisible;

  const VideoScreen({super.key, required this.isVisible});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final VideoLibrary _library = VideoLibrary.instance;
  LibraryStore? _store;

  @override
  void initState() {
    super.initState();
    _library.addListener(_onChanged);
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onChanged);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
    if (widget.isVisible) _loadIfNeeded();
  }

  @override
  void didUpdateWidget(VideoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _loadIfNeeded();
  }

  /// Loads the list the first time the tab is opened, so the permission
  /// prompt doesn't appear at app start for people who only want music.
  void _loadIfNeeded() {
    if (!_library.hasLoaded && !_library.isLoading) _library.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _library.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    super.dispose();
  }

  bool _isHidden(AssetEntity video) => _store?.isHidden(videoKey(video.id)) ?? false;

  List<AssetEntity> get _visible => _library.videos.where((v) => !_isHidden(v)).toList();

  List<AssetEntity> get _all => _visible.where((v) => !(_store?.isFilteredOut(videoKey(v.id)) ?? false)).toList();

  List<AssetEntity> get _favourites => _visible.where((v) => _store?.isFavourite(videoKey(v.id)) ?? false).toList();

  List<AssetEntity> get _latest => (_store?.latest ?? [])
      .map(videoIdOf)
      .whereType<String>()
      .map(_library.videoById)
      .whereType<AssetEntity>()
      .where((v) => !_isHidden(v))
      .toList();

  Future<void> _newPlaylist() async {
    String? name = await askPlaylistName(context);
    if (name != null) await _store?.createPlaylist(name, kind: MediaKind.video);
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: AppLogo(),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: "Refresh",
              icon: Icon(Icons.refresh),
              onPressed: _library.isLoading ? null : _library.load,
            ),
            PopupMenuButton<String>(
              tooltip: "More",
              onSelected: (action) => Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => action == "hidden" ? const HiddenScreen() : const TransferScreen(),
              )),
              itemBuilder: (context) => [
                PopupMenuItem(value: "hidden", child: Text("Hidden & filtered")),
                if (Platform.isAndroid) PopupMenuItem(value: "receive", child: Text("Receive files")),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 16),
            tabs: [Tab(text: "Videos"), Tab(text: "Favourites"), Tab(text: "Latest"), Tab(text: "Playlists")],
          ),
        ),
        body: _library.isLoading && _library.videos.isEmpty
            ? Center(child: CircularProgressIndicator())
            : _library.noPermission
                ? _message(
                    colors,
                    icon: Icons.video_library_outlined,
                    text: "Allow m6 player to see your videos to play them here.",
                    buttonLabel: "Allow access",
                    // A second request is usually blocked by the system: send people to Settings.
                    onPressed: PhotoManager.openSetting,
                  )
                : TabBarView(
                    children: [
                      _listOrMessage(colors, _all, ItemList.all, "Videos", "No videos on this phone yet."),
                      _listOrMessage(colors, _favourites, ItemList.favourites, "Favourites",
                          "No favourite videos yet. Use a video's ⋮ menu."),
                      _listOrMessage(
                          colors, _latest, ItemList.latest, "Latest", "Nothing in Latest yet. Use a video's ⋮ menu."),
                      _playlistsTab(colors),
                    ],
                  ),
      ),
    );
  }

  Widget _listOrMessage(ColorScheme colors, List<AssetEntity> videos, ItemList from, String name, String empty) {
    if (videos.isEmpty) return _message(colors, icon: Icons.videocam_off_outlined, text: empty);
    return VideoList(
      videos: videos,
      from: from,
      header: "$name (${videos.length})",
      onRefresh: from == ItemList.all ? _library.load : null,
    );
  }

  Widget _playlistsTab(ColorScheme colors) {
    List<Playlist> playlists = _store?.playlistsOf(MediaKind.video) ?? [];
    return ListView(
      padding: EdgeInsets.only(bottom: 8),
      children: [
        ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(48 * 0.08),
            ),
            child: Icon(Icons.add, color: colors.primary),
          ),
          title: Text("New playlist", style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600)),
          onTap: _newPlaylist,
        ),
        for (Playlist playlist in playlists)
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(48 * 0.08),
              ),
              child: Icon(Icons.video_library_outlined, color: colors.onSurfaceVariant),
            ),
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text("${playlist.songs.length} ${playlist.songs.length == 1 ? "video" : "videos"}",
                style: TextStyle(color: colors.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => PlaylistScreen(playlistId: playlist.id),
            )),
          ),
      ],
    );
  }

  Widget _message(ColorScheme colors,
      {required IconData icon, required String text, String? buttonLabel, VoidCallback? onPressed}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colors.onSurfaceVariant),
            SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (buttonLabel != null) ...[
              SizedBox(height: 20),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
