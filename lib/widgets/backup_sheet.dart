import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/library_store.dart';
import 'options_sheet.dart';

/// Back up & restore: saves favourites, Latest, playlists, hidden items, sort
/// choices, favourite stations and video positions to a file you can keep or
/// send to yourself, and loads such a file back. Songs themselves aren't in it.
Future<void> showBackupSheet(BuildContext context) {
  return showOptionsSheet(
    context,
    title: "Back up & restore",
    subtitle: "Playlists, favourites and settings (not the songs or videos)",
    options: [
      SheetOption(icon: Icons.upload_file, label: "Back up to a file", onTap: () => _backUp(context)),
      SheetOption(icon: Icons.settings_backup_restore, label: "Restore from a file", onTap: () => _restore(context)),
    ],
  );
}

void _say(BuildContext context, String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> _backUp(BuildContext context) async {
  try {
    LibraryStore store = await LibraryStore.instance();
    DateTime now = DateTime.now();
    String stamp = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    Directory temp = await getTemporaryDirectory();
    File file = File('${temp.path}/m6player-backup-$stamp.json');
    await file.writeAsString(store.backupJson());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], title: "M6 Player backup"));
  } catch (e) {
    debugPrint("Error backing up: $e");
    _say(context, "Couldn't make the backup");
  }
}

Future<void> _restore(BuildContext context) async {
  try {
    List<PlatformFile> picked = await FilePicker.pickFiles(type: FileType.any);
    String? path = picked.isEmpty ? null : picked.first.path;
    if (path == null || !context.mounted) return;
    bool? sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Restore this backup?"),
        content: Text("Your current playlists, favourites and settings will be replaced."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Restore")),
        ],
      ),
    );
    if (sure != true) return;
    LibraryStore store = await LibraryStore.instance();
    await store.restoreFrom(await File(path).readAsString());
    _say(context, "Backup restored");
  } on FormatException {
    _say(context, "That isn't an M6 Player backup");
  } catch (e) {
    debugPrint("Error restoring: $e");
    _say(context, "Couldn't restore the backup");
  }
}
