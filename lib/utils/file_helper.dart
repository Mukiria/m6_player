import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Opens file picker to select an MP3 file and returns the file.
Future<File?> pickMp3File() async {
  PlatformFile? picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['mp3'], // Forces MP3 files only
  );

  if (picked != null && picked.path != null) {
    return File(picked.path!);
  }
  return null;
}

/// The app's own music library folder. Picked songs are copied here so the
/// playlist survives restarts and removing a song never touches the original.
Future<Directory> libraryDirectory() async {
  Directory docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/music').create(recursive: true);
}

/// Returns all MP3s in [dir], oldest first (i.e. in the order they were added).
Future<List<File>> loadLibrary(Directory dir) async {
  List<File> files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.mp3'))
      .toList();
  files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
  return files;
}

/// Copies [source] into [dir], adding " (1)", " (2)", ... if the name is taken.
Future<File> importToLibrary(File source, Directory dir) async {
  String name = source.uri.pathSegments.last;
  int dot = name.lastIndexOf('.');
  String base = dot > 0 ? name.substring(0, dot) : name;
  String ext = dot > 0 ? name.substring(dot) : '';

  File target = File('${dir.path}/$name');
  for (int n = 1; target.existsSync(); n++) {
    target = File('${dir.path}/$base ($n)$ext');
  }
  return source.copy(target.path);
}

/// Deletes the app's copy of a song from the library.
Future<void> removeFromLibrary(File file) async {
  if (await file.exists()) await file.delete();
}
