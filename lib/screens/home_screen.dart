import 'package:flutter/material.dart';
import '../widgets/mini_player.dart';
import 'music_player_screen.dart';
import 'radio_screen.dart';
import 'video_screen.dart';

/// The app's main screen: Music, Radio and Video tabs with a bottom navigation bar,
/// and the mini player above it whenever something is playing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Both tabs stay alive, so the radio list and the library aren't reloaded on every switch.
      body: IndexedStack(
        index: _tab,
        children: [
          const MusicPlayerScreen(),
          const RadioScreen(),
          VideoScreen(isVisible: _tab == 2),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.music_note_outlined),
                selectedIcon: Icon(Icons.music_note),
                label: 'Music',
              ),
              NavigationDestination(
                icon: Icon(Icons.radio_outlined),
                selectedIcon: Icon(Icons.radio),
                label: 'Radio',
              ),
              NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library),
                label: 'Video',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
