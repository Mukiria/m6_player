import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'screens/home_screen.dart';
import 'services/audio_handler.dart';
import 'services/player_service.dart';
import 'theme.dart';

Future<void> main() async {
  // Keeps playback going in the background, with notification, lock-screen and
  // headset controls (see M6AudioHandler for the notification's buttons).
  await AudioService.init(
    builder: () => M6AudioHandler(PlayerService.instance),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.msixv.com.m6player.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_stat_m6', // White music note (the colour app icon shows as a blank square)
      notificationColor: brandBlue,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M6 Player',
      // Light or dark, following the phone's setting
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
