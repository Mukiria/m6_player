import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/utils/file_helper.dart';

void main() {
  late Directory temp;
  late Directory library;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('m6player_test');
    library = await Directory('${temp.path}/music').create();
  });

  tearDown(() => temp.delete(recursive: true));

  File source(String name) => File('${temp.path}/$name')..writeAsStringSync(name);

  test('importToLibrary copies the file and leaves the original', () async {
    final original = source('song.mp3');

    final copy = await importToLibrary(original, library);

    expect(copy.path, '${library.path}/song.mp3');
    expect(copy.readAsStringSync(), 'song.mp3');
    expect(original.existsSync(), isTrue);
  });

  test('importToLibrary numbers duplicate names', () async {
    final original = source('song.mp3');

    await importToLibrary(original, library);
    final second = await importToLibrary(original, library);
    final third = await importToLibrary(original, library);

    expect(second.path, '${library.path}/song (1).mp3');
    expect(third.path, '${library.path}/song (2).mp3');
  });

  test('loadLibrary returns only MP3s, oldest first', () async {
    final a = await importToLibrary(source('a.mp3'), library);
    final b = await importToLibrary(source('b.MP3'), library);
    await importToLibrary(source('notes.txt'), library);
    b.setLastModifiedSync(DateTime(2020));
    a.setLastModifiedSync(DateTime(2021));

    final files = await loadLibrary(library);

    expect(files.map((f) => f.path), [b.path, a.path]);
  });

  test('removeFromLibrary deletes only the library copy', () async {
    final original = source('song.mp3');
    final copy = await importToLibrary(original, library);

    await removeFromLibrary(copy);

    expect(copy.existsSync(), isFalse);
    expect(original.existsSync(), isTrue);
    await removeFromLibrary(copy); // Removing twice is a no-op
  });
}
