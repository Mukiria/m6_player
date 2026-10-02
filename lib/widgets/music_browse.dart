import 'dart:io';
import 'package:flutter/material.dart';
import '../services/library_store.dart';
import '../services/music_library.dart';
import '../services/track_info.dart';
import 'artwork.dart';
import 'song_list.dart';

/// Rebuilds when songs are added or removed, or hidden.
Listenable _changes() => Listenable.merge([MusicLibrary.instance, ?LibraryStore.loaded]);

/// What the Browse tab groups songs by.
enum BrowseBy {
  albums('Albums', 'Unknown album'),
  artists('Artists', 'Unknown artist');

  final String label;
  final String unknown;
  const BrowseBy(this.label, this.unknown);

  /// The group a song belongs to.
  String groupOf(TrackInfo info) {
    String name = ((this == albums ? info.album : info.artist) ?? '').trim();
    return name.isEmpty ? unknown : name;
  }
}

/// The Music tab's Browse page: songs grouped by album or artist. Tapping a
/// group opens its songs. Hidden songs are left out.
class MusicBrowse extends StatefulWidget {
  const MusicBrowse({super.key});

  @override
  State<MusicBrowse> createState() => _MusicBrowseState();
}

class _MusicBrowseState extends State<MusicBrowse> {
  BrowseBy _by = BrowseBy.albums;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _changes(),
      builder: (context, _) {
        Map<String, List<File>> groups = browseGroups(_by);
        List<String> names = groups.keys.toList()
          ..sort((a, b) {
            // "Unknown ..." goes last, the rest A to Z
            bool unknownA = a == _by.unknown, unknownB = b == _by.unknown;
            if (unknownA != unknownB) return unknownA ? 1 : -1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  for (BrowseBy by in BrowseBy.values)
                    ChoiceChip(label: Text(by.label), selected: by == _by, onSelected: (_) => setState(() => _by = by)),
                ],
              ),
            ),
            Expanded(
              child: names.isEmpty
                  ? Center(child: Text("No songs yet", style: TextStyle(color: colors.onSurfaceVariant)))
                  : ListView.builder(
                      itemCount: names.length,
                      itemBuilder: (context, index) {
                        String name = names[index];
                        List<File> songs = groups[name]!;
                        return ListTile(
                          leading: Artwork(size: 48, coverPath: _cover(songs)),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(songs.length == 1 ? "1 song" : "${songs.length} songs"),
                          trailing: Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => BrowseGroupScreen(by: _by, name: name),
                          )),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  String? _cover(List<File> songs) {
    for (File song in songs) {
      String? cover = TrackInfoService.instance.infoFor(song).coverPath;
      if (cover != null) return cover;
    }
    return null;
  }
}

/// The library's songs (not hidden) grouped by [by], each group in the order added.
Map<String, List<File>> browseGroups(BrowseBy by) {
  Map<String, List<File>> groups = {};
  for (File song in MusicLibrary.instance.songs) {
    if (_isHidden(song)) continue;
    groups.putIfAbsent(by.groupOf(TrackInfoService.instance.infoFor(song)), () => []).add(song);
  }
  return groups;
}

bool _isHidden(File song) {
  // The store loads once at start-up; until then nothing is hidden.
  LibraryStore? store = LibraryStore.loaded;
  return store?.isHidden(songKey(song)) ?? false;
}

/// One album's or artist's songs.
class BrowseGroupScreen extends StatelessWidget {
  final BrowseBy by;
  final String name;

  const BrowseGroupScreen({super.key, required this.by, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListenableBuilder(
        listenable: _changes(),
        builder: (context, _) {
          List<File> songs = browseGroups(by)[name] ?? [];
          if (songs.isEmpty) return Center(child: Text("No songs"));
          return SongList(
            songs: songs,
            queueId: '${by.name}:$name',
            header: songs.length == 1 ? "1 song" : "${songs.length} songs",
          );
        },
      ),
    );
  }
}
