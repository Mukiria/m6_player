import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';

/// Opens the file picker to select one or more MP3s. Empty if cancelled.
Future<List<File>> pickMp3Files() async {
  List<PlatformFile> picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['mp3'], // Forces MP3 files only
  );
  return picked.where((file) => file.path != null).map((file) => File(file.path!)).toList();
}

/// Lets the user choose a folder. Null if cancelled.
Future<Directory?> pickFolder() async {
  String? path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a music folder');
  return path == null ? null : Directory(path);
}

/// Asks for permission to read the phone's audio files, needed to look inside
/// a folder the user picked (Android only; iOS grants access through the picker).
Future<bool> requestAudioPermission() async {
  if (!Platform.isAndroid) return true;
  // photo_manager asks for the audio permission on Android 13+ and the storage one on older versions.
  PermissionState state = await PhotoManager.requestPermissionExtend(
    requestOption: PermissionRequestOption(
      androidPermission: AndroidPermission(type: RequestType.audio, mediaLocation: false),
    ),
  );
  return state.hasAccess;
}

/// All MP3s in [dir] and its subfolders, sorted by path (so albums stay in order).
Future<List<File>> findMp3s(Directory dir) async {
  List<File> files = await dir
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.mp3'))
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return files;
}

/// True if [library] already has a copy of [source]: same file name and size.
/// Stops a folder that is added twice from duplicating every song.
bool isInLibrary(File source, List<File> library) {
  String name = source.uri.pathSegments.last;
  int size = source.lengthSync();
  return library.any((file) => file.uri.pathSegments.last == name && file.lengthSync() == size);
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
