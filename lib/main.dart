import 'package:flutter/material.dart';
import 'screens/music_player_screen.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request storage permission before running the app
  await requestStoragePermission();

  runApp(MyApp());
}

/// Requests storage permission at startup
Future<void> requestStoragePermission() async {
  if (!await Permission.storage.request().isGranted) {
    print("Storage permission denied");
  } else {
    print("Storage permission granted");
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MusicPlayerScreen(),
    );
  }
}
