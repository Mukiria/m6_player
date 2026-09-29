import 'package:file_picker/file_picker.dart';
import 'dart:io';

/// Opens file picker to select an MP3 file and returns the file.
Future<File?> pickMp3File() async {
  PlatformFile? picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['mp3'], // Forces MP3 files only
  );

  if (picked != null && picked.path != null) {
    print("File picked: ${picked.path}");
    return File(picked.path!);
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
