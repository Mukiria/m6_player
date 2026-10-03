import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../services/radio_api.dart';
import '../services/track_info.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_menu.dart';
import '../widgets/artwork.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/playlist_picker.dart';
import '../widgets/tab_background.dart';
import 'playlist_screen.dart';
import 'quick_list_screen.dart';

/// The Home tab, "My Listen": the user's playlists (with their own cover photos),
/// songs to carry on with, a featured playlist and recently played radio stations.
class HomeTab extends StatefulWidget {
  /// The empty-state buttons: open the add-songs menu, or go to the Radio tab.
  final VoidCallback onAddSongs;
  final VoidCallback onBrowseRadio;

  const HomeTab({super.key, required this.onAddSongs, required this.onBrowseRadio});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final MusicLibrary _library = MusicLibrary.instance;
  final PlayerService _service = PlayerService.instance;
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
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _library.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    super.dispose();
  }

  void _open(Playlist playlist) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => PlaylistScreen(playlistId: playlist.id)));

  Future<void> _newPlaylist() async {
    String? name = await askPlaylistName(context);
    if (name != null) await _store?.createPlaylist(name);
  }

  /// Songs played before, most recent first (hidden ones left out).
  List<File> get _recentSongs {
    LibraryStore? store = _store;
    if (store == null) return [];
    List<(File, DateTime)> played = [
      for (File song in _library.songs)
        if (!store.isHidden(songKey(song)) && store.lastPlayed(songKey(song)) != null)
          (song, store.lastPlayed(songKey(song))!),
    ];
    played.sort((a, b) => b.$2.compareTo(a.$2));
    return played.take(12).map((p) => p.$1).toList();
  }

  List<File> _songsOf(Playlist playlist) {
    LibraryStore? store = _store;
    return playlist.songs
        .where((key) => !(store?.isHidden(key) ?? false))
        .map(_library.songNamed)
        .whereType<File>()
        .toList();
  }

  Future<void> _playStation(RadioStation station) async {
    try {
      await _service.playStream(station.url, station.name);
      _store?.addRadioRecent(station);
    } catch (e) {
      debugPrint("Error playing radio: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't play ${station.name}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    List<Playlist> playlists = _store?.playlists ?? [];
    List<File> recent = _recentSongs;
    Playlist? featured = playlists.where((p) => p.kind == MediaKind.audio && _songsOf(p).isNotEmpty).firstOrNull;
    List<RadioStation> stations = _store?.radioRecent.take(12).toList() ?? [];

    return TabBackground(
      image: 'assets/backgrounds/transfer.jpg',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: AppLogo(),
          centerTitle: false,
          actions: [const SearchButton(), const AppMenuButton()],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text("My Listen", style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700))),
                _PillButton(icon: Icons.add, label: "New playlist", onTap: _newPlaylist),
              ],
            ),
            SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                double gap = 16;
                double tile = (box.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: 20,
                  children: [
                    _quickTile(QuickList.favourites, tile, colors),
                    _quickTile(QuickList.latest, tile, colors),
                    for (Playlist p in playlists) _playlistTile(p, tile, colors),
                  ],
                );
              },
            ),
            if (_library.songs.isEmpty && playlists.isEmpty) ...[
              SizedBox(height: 24),
              _emptyCard(colors),
            ],
            if (recent.isNotEmpty) ...[
              _heading("Continue listening"),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recent.length,
                  separatorBuilder: (context, i) => SizedBox(width: 14),
                  itemBuilder: (context, i) => _songCard(recent, i, colors),
                ),
              ),
            ],
            if (featured != null) ...[
              SizedBox(height: 28),
              _featuredCard(featured, colors),
            ],
            if (stations.isNotEmpty) ...[
              _heading("Recent radio"),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stations.length,
                  separatorBuilder: (context, i) => SizedBox(width: 14),
                  itemBuilder: (context, i) => _stationCard(stations[i], colors),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: EdgeInsets.only(top: 28, bottom: 12),
        child: Text(text, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      );

  /// A card on the page: its usual tint, or white in dark mode (its contents then use the light theme, so the text stays dark).
  Widget _card({required Color tint, required double radius, required EdgeInsets padding, required Widget child}) {
    bool dark = Theme.of(context).brightness == Brightness.dark;
    Widget card = Container(
      padding: padding,
      decoration: BoxDecoration(color: dark ? Colors.white : tint, borderRadius: BorderRadius.circular(radius)),
      // A Material here gives the text the (light) theme's default style, and the rows their ink
      child: Material(type: MaterialType.transparency, child: child),
    );
    return dark ? Theme(data: lightTheme(), child: card) : card;
  }

  Widget _emptyCard(ColorScheme colors) {
    // Very transparent in both modes: black on light, white on dark (the same strength)
    bool dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.library_music_outlined, size: 48, color: colors.onSurfaceVariant),
          SizedBox(height: 12),
          Text("Start your library", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text("Add songs from your phone, or tune in to a radio station.",
              textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
          SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: brandOrange, foregroundColor: Colors.white),
                onPressed: widget.onAddSongs,
                icon: Icon(Icons.add),
                label: Text("Add songs"),
              ),
              OutlinedButton.icon(
                onPressed: widget.onBrowseRadio,
                icon: Icon(Icons.radio),
                label: Text("Browse radio"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Favourites and Latest, always there as the first two tiles.
  Widget _quickTile(QuickList list, double size, ColorScheme colors) {
    bool favourites = list == QuickList.favourites;
    List<File> songs = QuickListScreen.songsOf(list, _store);
    int count = songs.length;
    bool dark = Theme.of(context).brightness == Brightness.dark;
    return _tile(
      size: size,
      cover: ListCover(
        keys: songs.map(songKey).toList(),
        size: size,
        m6Icon: favourites ? 'heart' : 'new',
        whitePlaceholder: dark, // White in dark mode, the brand gradient in light mode
      ),
      name: favourites ? "Favourites" : "Latest",
      subtitle: count == 0
          ? (favourites ? "" : "Songs you add here")
          : "$count ${count == 1 ? "song" : "songs"}",
      // "Tap [heart outline] on a song": white outline in dark mode, black in light, no fill
      subtitleWidget: count == 0 && favourites
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: "Tap "),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.favorite_border, size: 16, color: dark ? Colors.white : Colors.black),
                  ),
                  TextSpan(text: " on a song"),
                ],
              ),
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          : null,
      colors: colors,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => QuickListScreen(list: list))),
    );
  }

  /// One tile of the grid: the cover (with an optional ⋮ menu over it), a name and a line under it.
  Widget _tile({
    required double size,
    required Widget cover,
    required String name,
    required String subtitle,
    Widget? subtitleWidget,
    required ColorScheme colors,
    required VoidCallback onTap,
    Widget? menu,
  }) {
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(children: [cover, if (menu != null) Positioned(top: 4, right: 4, child: menu)]),
            SizedBox(height: 8),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            subtitleWidget ?? Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _playlistTile(Playlist playlist, double size, ColorScheme colors) {
    int count = playlist.songs.length;
    String noun = playlist.kind == MediaKind.video ? (count == 1 ? "video" : "videos") : (count == 1 ? "song" : "songs");
    return _tile(
      size: size,
      cover: PlaylistCover(playlist: playlist, size: size),
      name: playlist.name,
      subtitle: "$count $noun",
      colors: colors,
      onTap: () => _open(playlist),
      menu: PopupMenuButton<String>(
        tooltip: "Cover photo",
        icon: Icon(Icons.more_vert, color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
        onSelected: (action) => action == "cover" ? chooseCoverPhoto(context, playlist) : removeCoverPhoto(playlist),
        itemBuilder: (context) => [
          PopupMenuItem(value: "cover", child: Text(playlist.coverPath == null ? "Add cover photo" : "Change cover photo")),
          if (playlist.coverPath != null) PopupMenuItem(value: "remove", child: Text("Remove cover photo")),
        ],
      ),
    );
  }

  Widget _songCard(List<File> songs, int i, ColorScheme colors) {
    TrackInfo info = TrackInfoService.instance.infoFor(songs[i]);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _service.playQueue('recent', songs, i),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(size: 112, coverPath: info.coverPath),
            SizedBox(height: 6),
            Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600)),
            Text(info.artist ?? "", maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _featuredCard(Playlist playlist, ColorScheme colors) {
    List<File> songs = _songsOf(playlist);
    if (Theme.of(context).brightness == Brightness.dark) colors = lightTheme().colorScheme;
    return _card(
      tint: colors.surfaceContainer,
      radius: 24,
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlaylistCover(playlist: playlist, size: 96),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.15)),
                    SizedBox(height: 4),
                    Text("${songs.length} ${songs.length == 1 ? "track" : "tracks"}",
                        style: TextStyle(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _open(playlist),
                child: Text("More", style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          SizedBox(height: 8),
          for (int i = 0; i < songs.length && i < 3; i++) _trackRow(playlist, songs, i, colors),
        ],
      ),
    );
  }

  Widget _trackRow(Playlist playlist, List<File> songs, int i, ColorScheme colors) {
    TrackInfo info = TrackInfoService.instance.infoFor(songs[i]);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Artwork(size: 48, coverPath: info.coverPath),
      title: Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(info.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _service.playQueue(playlist.id, songs, i),
    );
  }

  Widget _stationCard(RadioStation station, ColorScheme colors) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _playStation(station),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Artwork(size: 72, isRadio: true, round: true),
            SizedBox(height: 6),
            Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A small rounded orange button with white text.
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PillButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: brandOrange,
      shape: StadiumBorder(),
      child: InkWell(
        customBorder: StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
