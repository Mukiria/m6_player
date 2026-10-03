import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/player_service.dart';
import '../services/track_info.dart';
import '../widgets/item_actions.dart';
import '../widgets/song_list.dart';

/// Which of the two built-in lists to open from Home.
enum QuickList { favourites, latest }

/// Favourites or Latest as a page of its own (the same lists as the Music tab's
/// tabs, hidden songs left out).
class QuickListScreen extends StatefulWidget {
  final QuickList list;

  const QuickListScreen({super.key, required this.list});

  /// Songs in the list, as the Music tab shows them.
  static List<File> songsOf(QuickList list, LibraryStore? store) {
    if (store == null) return [];
    MusicLibrary library = MusicLibrary.instance;
    switch (list) {
      case QuickList.favourites:
        return sortSongs(library.songs, store.sort, TrackInfoService.instance.infoFor)
            .where((s) => !store.isHidden(songKey(s)) && store.isFavourite(songKey(s)))
            .toList();
      case QuickList.latest:
        return store.latest.map(library.songNamed).whereType<File>().where((s) => !store.isHidden(songKey(s))).toList();
    }
  }

  @override
  State<QuickListScreen> createState() => _QuickListScreenState();
}

class _QuickListScreenState extends State<QuickListScreen> {
  LibraryStore? _store;

  @override
  void initState() {
    super.initState();
    MusicLibrary.instance.addListener(_onChanged);
    LibraryStore.instance().then((store) {
      if (!mounted) return;
      store.addListener(_onChanged);
      setState(() => _store = store);
    }).catchError((Object e) => debugPrint("Error opening the library store: $e"));
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    MusicLibrary.instance.removeListener(_onChanged);
    _store?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool favourites = widget.list == QuickList.favourites;
    String title = favourites ? "Favourites" : "Latest";
    List<File> songs = QuickListScreen.songsOf(widget.list, _store);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: songs.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  favourites
                      ? "No favourites yet. Tap the heart on Now Playing, or use a song's ⋮ menu."
                      : "Nothing in Latest yet. Use a song's ⋮ menu, Add to…, Latest.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            )
          : SongList(
              songs: songs,
              queueId: favourites ? PlayerService.favouritesQueue : PlayerService.latestQueue,
              from: favourites ? ItemList.favourites : ItemList.latest,
              header: "$title (${songs.length})",
            ),
    );
  }
}
