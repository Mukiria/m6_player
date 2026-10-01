import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/services/track_info.dart';

/// Builds a small MP3 tag (ID3v2.3) with text frames and an optional cover picture.
Uint8List id3Tag({Map<String, String> text = const {}, List<int>? png}) {
  List<int> frame(String id, List<int> content) {
    int size = content.length;
    return [...ascii.encode(id), size >> 24 & 0xFF, size >> 16 & 0xFF, size >> 8 & 0xFF, size & 0xFF, 0, 0, ...content];
  }

  List<int> body = [
    for (MapEntry<String, String> entry in text.entries) ...frame(entry.key, [0, ...latin1.encode(entry.value)]),
    // APIC: text encoding, MIME type, picture type 3 (front cover), empty description, image data
    if (png != null) ...frame('APIC', [0, ...ascii.encode('image/png'), 0, 3, 0, ...png]),
  ];
  int size = body.length; // Tag size is "syncsafe": 7 bits per byte
  return Uint8List.fromList([
    ...ascii.encode('ID3'), 3, 0, 0,
    size >> 21 & 0x7F, size >> 14 & 0x7F, size >> 7 & 0x7F, size & 0x7F,
    ...body,
  ]);
}

void main() {
  late Directory temp;
  late Directory covers;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('m6player_tags');
    covers = await Directory('${temp.path}/covers').create();
  });

  tearDown(() => temp.delete(recursive: true));

  test('reads title, artist and album, and saves the cover', () {
    List<int> png = [0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4];
    File song = File('${temp.path}/01 track.mp3')
      ..writeAsBytesSync(id3Tag(text: {'TIT2': 'Malaika', 'TPE1': 'Miriam Makeba', 'TALB': 'Pata Pata'}, png: png));

    TrackInfo info = readTrackInfo(song, covers.path);

    expect(info.title, 'Malaika');
    expect(info.artist, 'Miriam Makeba');
    expect(info.album, 'Pata Pata');
    expect(info.subtitle, 'Miriam Makeba · Pata Pata');
    expect(info.coverPath, '${covers.path}/01 track.mp3.png');
    expect(File(info.coverPath!).readAsBytesSync(), png);

    // Read again: the saved cover is reused rather than extracted a second time.
    expect(readTrackInfo(song, covers.path).coverPath, info.coverPath);
  });

  test('falls back to the file name when there are no tags', () {
    File song = File('${temp.path}/My Song.mp3')..writeAsStringSync('not really an mp3');

    TrackInfo info = readTrackInfo(song, covers.path);

    expect(info.title, 'My Song');
    expect(info.artist, isNull);
    expect(info.coverPath, isNull);
    expect(info.subtitle, 'Unknown artist');
  });

  test('blank tags count as missing', () {
    File song = File('${temp.path}/Fallback.mp3')..writeAsBytesSync(id3Tag(text: {'TIT2': '  ', 'TPE1': 'Sauti Sol'}));

    TrackInfo info = readTrackInfo(song, covers.path);

    expect(info.title, 'Fallback');
    expect(info.subtitle, 'Sauti Sol');
  });
}
