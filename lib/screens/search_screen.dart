import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/track_info.dart';
import '../services/video_library.dart';
import '../widgets/song_list.dart';
import '../widgets/video_list.dart';
import 'playlist_screen.dart';

/// Search across the songs (title, artist, album) and videos (name) on the
/// phone. Hidden items are left out, as they are everywhere else.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final MusicLibrary _music = MusicLibrary.instance;
  final VideoLibrary _videos = VideoLibrary.instance;
  final TextEditingController _controller = TextEditingController();
  LibraryStore? _store;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _music.addListener(_onChanged);
    _videos.addListener(_onChanged);
    _music.load();
    if (!_videos.hasLoaded) _videos.load();
    LibraryStore.instance().then((store) {
      if (mounted) setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _music.removeListener(_onChanged);
    _videos.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String? text) => text != null && text.toLowerCase().contains(_query);

  List<File> get _songResults {
    if (_query.isEmpty) return [];
    return _music.songs.where((song) {
      if (_store?.isHidden(songKey(song)) ?? false) return false;
      TrackInfo info = TrackInfoService.instance.infoFor(song);
      return _matches(info.title) || _matches(info.artist) || _matches(info.album);
    }).toList();
  }

  List<AssetEntity> get _videoResults {
    if (_query.isEmpty) return [];
    return _videos.videos.where((video) {
      if (_store?.isHidden(videoKey(video.id)) ?? false) return false;
      return _matches(videoTitle(video));
    }).toList();
  }

  List<Playlist> get _playlistResults {
    if (_query.isEmpty) return [];
    return (_store?.playlists ?? []).where((p) => _matches(p.name)).toList();
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    List<File> songs = _songResults;
    List<AssetEntity> videos = _videoResults;
    List<Playlist> playlists = _playlistResults;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(hintText: "Search songs, videos and playlists", border: InputBorder.none),
            onChanged: (text) => setState(() => _query = text.trim().toLowerCase()),
          ),
          actions: [
            if (_query.isNotEmpty)
              IconButton(
                tooltip: "Clear",
                icon: Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  setState(() => _query = '');
                },
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: "Songs (${songs.length})"),
              Tab(text: "Videos (${videos.length})"),
              Tab(text: "Playlists (${playlists.length})"),
            ],
          ),
        ),
        body: _query.isEmpty
            ? Center(child: Text("Type to search", style: TextStyle(color: colors.onSurfaceVariant)))
            : TabBarView(
                children: [
                  songs.isEmpty
                      ? _none(colors)
                      : SongList(key: ValueKey('songs:$_query'), songs: songs, queueId: 'search:$_query'),
                  videos.isEmpty ? _none(colors) : VideoList(videos: videos),
                  playlists.isEmpty
                      ? _none(colors)
                      : ListView(
                          children: [
                            for (Playlist playlist in playlists)
                              ListTile(
                                leading: Icon(playlist.kind == MediaKind.audio ? Icons.queue_music : Icons.video_library_outlined),
                                title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    "${playlist.songs.length} ${playlist.kind == MediaKind.audio ? "songs" : "videos"}",
                                    style: TextStyle(color: colors.onSurfaceVariant)),
                                trailing: Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (context) => PlaylistScreen(playlistId: playlist.id))),
                              ),
                          ],
                        ),
                ],
              ),
      ),
    );
  }

  Widget _none(ColorScheme colors) =>
      Center(child: Text("Nothing found", style: TextStyle(color: colors.onSurfaceVariant)));
}
