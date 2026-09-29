import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/music_player_screen.dart';

Future<void> main() async {
  // Keeps playback going in the background, with lock-screen/notification controls
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.msixv.com.m6player.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFFF1552C)),
      ),
      home: const MusicPlayerScreen(),
    );
  }
}
