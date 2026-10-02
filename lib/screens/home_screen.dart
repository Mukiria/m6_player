import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import 'music_player_screen.dart';
import 'onboarding_screen.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // First run: the intro pages come first, then the permission prompt.
      if (!AppSettings.instance.onboarded && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (context) => const OnboardingScreen()));
      }
      // Before anything plays, so the system prompt can't interrupt the first song.
      PlayerService.instance.askForNotifications();
    });
  }

  /// Both tabs stay alive, so the radio list and the library aren't reloaded on
  /// every switch (or when the phone turns between portrait and landscape).
  final GlobalKey _tabsKey = GlobalKey();

  static const List<(IconData, IconData, String)> _destinations = [
    (Icons.music_note_outlined, Icons.music_note, 'Music'),
    (Icons.radio_outlined, Icons.radio, 'Radio'),
    (Icons.video_library_outlined, Icons.video_library, 'Video'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget tabs = IndexedStack(
      key: _tabsKey,
      index: _tab,
      children: [
        const MusicPlayerScreen(),
        const RadioScreen(),
        VideoScreen(isVisible: _tab == 2),
      ],
    );

    // Tablets and phones on their side: the tabs go down the left edge, which
    // leaves the full height for the lists, and the mini player sits under the content.
    if (MediaQuery.sizeOf(context).width >= 600) {
      return Scaffold(
        // The tabs' own app bars cover the top; the rail covers the left (a notch on a phone on its side).
        body: SafeArea(
          top: false,
          left: false,
          child: Row(
            children: [
              SafeArea(
                right: false,
                bottom: false,
                child: NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (index) => setState(() => _tab = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (var (icon, selectedIcon, label) in _destinations)
                      NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: Text(label)),
                  ],
                ),
              ),
              VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: tabs),
                    const MiniPlayer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: tabs,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            destinations: [
              for (var (icon, selectedIcon, label) in _destinations)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: label),
            ],
          ),
        ],
      ),
    );
  }
}
