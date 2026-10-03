import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../services/track_info.dart';
import '../utils/file_helper.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_menu.dart';
import '../widgets/item_actions.dart';
import '../widgets/music_browse.dart';
import '../widgets/pill_tab_bar.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/song_list.dart';
import '../widgets/tab_background.dart';
import 'playlist_screen.dart';
import 'smart_playlist_screen.dart';

/// The Music tab: Songs, Favourites, Latest and Playlists, with sorting and
/// adding music. Hidden songs are left out of every list, filtered-out ones out
/// of Songs. The playback controls live in the mini player and Now Playing.
class MusicPlayerScreen extends StatefulWidget {
  /// Bumped (by Home's "Add songs" button) to open this tab's add-songs menu.
  static final ValueNotifier<int> addSongsRequests = ValueNotifier(0);

  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final MusicLibrary _library = MusicLibrary.instance;
  final PlayerService _service = PlayerService.instance;
  LibraryStore? _store;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    MusicPlayerScreen.addSongsRequests.addListener(_onAddSongsRequested);
    _library.addListener(_onChanged);
    _library.load();
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onChanged);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onChanged() => setState(() {});

  void _onAddSongsRequested() {
    if (mounted && !_isImporting) _showAddOptions();
  }

  @override
  void dispose() {
    MusicPlayerScreen.addSongsRequests.removeListener(_onAddSongsRequested);
    _library.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    super.dispose();
  }

  SortOrder get _sort => _store?.sort ?? SortOrder.dateAdded;

  bool _isHidden(File song) => _store?.isHidden(songKey(song)) ?? false;

  /// Every song that isn't hidden, in the chosen order (filtered-out ones included).
  List<File> get _visibleSongs =>
      sortSongs(_library.songs, _sort, TrackInfoService.instance.infoFor).where((s) => !_isHidden(s)).toList();

  /// The Songs list: visible songs minus the filtered-out ones.
  List<File> get _sortedSongs => _visibleSongs.where((s) => !(_store?.isFilteredOut(songKey(s)) ?? false)).toList();

  List<File> get _favourites =>
      _visibleSongs.where((song) => _store?.isFavourite(songKey(song)) ?? false).toList();

  /// Latest, newest addition first.
  List<File> get _latest => (_store?.latest ?? [])
      .map(_library.songNamed)
      .whereType<File>()
      .where((song) => !_isHidden(song))
      .toList();

  Future<void> _setSort(SortOrder sort) async {
    await _store?.setSort(sort);
    // If one of these lists is playing, carry on in the new order.
    await _service.reorderQueue(PlayerService.allSongsQueue, _sortedSongs);
    await _service.reorderQueue(PlayerService.favouritesQueue, _favourites);
  }

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
        _showMessage("M6 Player needs permission to read your music to add a folder.");
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

  Future<void> _import(List<File> picked) async {
    if (picked.isEmpty) return;
    setState(() => _isImporting = true);
    final (int added, int skipped) = await _library.importSongs(picked);
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

  Future<void> _newPlaylist() async {
    String? name = await askPlaylistName(context);
    if (name != null) await _store?.createPlaylist(name);
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return TabBackground(
      image: 'assets/backgrounds/music.jpg',
      child: DefaultTabController(
        length: 5,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: AppLogo(),
            centerTitle: false,
            actions: [
              PopupMenuButton<SortOrder>(
                tooltip: "Sort",
                icon: Icon(Icons.sort),
                onSelected: _setSort,
                itemBuilder: (context) => [
                  for (SortOrder order in SortOrder.values)
                    CheckedPopupMenuItem(value: order, checked: order == _sort, child: Text(order.label)),
                ],
              ),
              IconButton(
                tooltip: "Add songs",
                icon: Icon(Icons.add),
                onPressed: _isImporting ? null : _showAddOptions,
              ),
              const SearchButton(),
              const AppMenuButton(),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(54),
              child: Column(
                children: [
                  PillTabBar(labels: ["Songs", "Browse", "Favourites", "Latest", "Playlists"]),
                  SizedBox(height: 2, child: _isImporting ? LinearProgressIndicator(minHeight: 2) : null),
                ],
              ),
            ),
          ),
          body: TabBarView(
            children: [
              _songsTab(colors),
              MusicBrowse(),
              _favouritesTab(colors),
              _latestTab(colors),
              _playlistsTab(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _songsTab(ColorScheme colors) {
    List<File> songs = _sortedSongs;
    if (songs.isEmpty) {
      return _message(
        colors,
        icon: Icons.library_music_outlined,
        title: "No songs yet",
        text: "Add MP3s or a music folder from your phone.",
        button: FilledButton.icon(
          onPressed: _isImporting ? null : _showAddOptions,
          icon: Icon(Icons.add),
          label: Text("Add songs"),
        ),
      );
    }
    return SongList(
      songs: songs,
      queueId: PlayerService.allSongsQueue,
      header: "Songs (${songs.length}) · ${_sort.label}",
    );
  }

  Widget _favouritesTab(ColorScheme colors) {
    List<File> favourites = _favourites;
    if (favourites.isEmpty) {
      return _message(
        colors,
        icon: Icons.favorite_border,
        title: "No favourites yet",
        text: "Tap the heart on Now Playing, or use a song's ⋮ menu.",
      );
    }
    return SongList(
      songs: favourites,
      queueId: PlayerService.favouritesQueue,
      from: ItemList.favourites,
      header: "Favourites (${favourites.length})",
    );
  }

  Widget _latestTab(ColorScheme colors) {
    List<File> latest = _latest;
    if (latest.isEmpty) {
      return _message(
        colors,
        icon: Icons.fiber_new_outlined,
        title: "Nothing in Latest yet",
        text: "Use a song's ⋮ menu, Add to…, Latest.",
      );
    }
    return SongList(
      songs: latest,
      queueId: PlayerService.latestQueue,
      from: ItemList.latest,
      header: "Latest (${latest.length})",
    );
  }

  Widget _playlistsTab(ColorScheme colors) {
    List<Playlist> playlists = _store?.playlistsOf(MediaKind.audio) ?? [];
    return ListView(
      padding: EdgeInsets.only(bottom: 8),
      children: [
        SmartPlaylistTiles(kind: MediaKind.audio),
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
        for (Playlist playlist in playlists) _playlistTile(playlist, colors),
      ],
    );
  }

  Widget _playlistTile(Playlist playlist, ColorScheme colors) {
    int count = playlist.songs.length;
    return ListTile(
      leading: PlaylistCover(playlist: playlist, size: 48),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text("$count ${count == 1 ? "song" : "songs"}", style: TextStyle(color: colors.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => PlaylistScreen(playlistId: playlist.id),
      )),
    );
  }

  Widget _message(ColorScheme colors,
      {required IconData icon, required String title, required String text, Widget? button}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colors.onSurfaceVariant),
            SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 18)),
            SizedBox(height: 4),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
            if (button != null) ...[SizedBox(height: 20), button],
          ],
        ),
      ),
    );
  }
}
