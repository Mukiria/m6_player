import 'package:file_picker/file_picker.dart';
import 'dart:io';

/// Opens file picker to select an MP3 file and returns the file.
Future<File?> pickMp3File() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['mp3'], // Forces MP3 files only
  );

  if (result != null && result.files.single.path != null) {
    print("File picked: ${result.files.single.path}");
    return File(result.files.single.path!);
  }

  print("No file selected");
  return null;
}

/// Deletes an MP3 file from the storage.
void deleteFile(String path) {
  File file = File(path);
  if (file.existsSync()) {
    file.deleteSync();
    print("File deleted: $path");
  }
}
