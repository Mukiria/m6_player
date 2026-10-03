import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../theme.dart';
import '../widgets/mini_player.dart';
import 'home_tab.dart';
import 'music_player_screen.dart';
import 'onboarding_screen.dart';
import 'radio_screen.dart';
import 'video_screen.dart';

/// The app's main screen: Home, Music, Radio and Video tabs with a floating bottom
/// navigation bar on an orange block, and the mini player above it whenever something is playing.
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
      // First run: the intro pages.
      if (!AppSettings.instance.onboarded && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (context) => const OnboardingScreen()));
      }
    });
  }

  /// Both tabs stay alive, so the radio list and the library aren't reloaded on
  /// every switch (or when the phone turns between portrait and landscape).
  final GlobalKey _tabsKey = GlobalKey();

  static const List<(IconData, IconData, String)> _destinations = [
    (Icons.home_outlined, Icons.home, 'Home'),
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
        HomeTab(
          onAddSongs: () {
            setState(() => _tab = 1);
            MusicPlayerScreen.addSongsRequests.value++;
          },
          onBrowseRadio: () => setState(() => _tab = 2),
        ),
        const MusicPlayerScreen(),
        const RadioScreen(),
        VideoScreen(isVisible: _tab == 3),
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
                    Container(color: brandOrange, child: const MiniPlayer()),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // The orange block: mini player on top (with its progress track), then the nav in a rounded pill.
    return Scaffold(
      body: tabs,
      bottomNavigationBar: Container(
        color: brandOrange,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: _NavPill(
                  selected: _tab,
                  onSelected: (index) => setState(() => _tab = index),
                  destinations: _destinations,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating rounded bar of tab buttons: the open one is solid orange, the rest are plain.
class _NavPill extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  final List<(IconData, IconData, String)> destinations;

  const _NavPill({required this.selected, required this.onSelected, required this.destinations});

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? brandNavyRaised : Color(0xFFFDFDFD),
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: EdgeInsets.all(6),
        child: Row(
          children: [
            for (int i = 0; i < destinations.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == selected,
                  label: destinations[i].$3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => onSelected(i),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 180),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: i == selected ? brandOrange : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(i == selected ? destinations[i].$2 : destinations[i].$1,
                              size: 24, color: i == selected ? Colors.white : colors.onSurfaceVariant),
                          SizedBox(height: 2),
                          Text(
                            destinations[i].$3,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == selected ? FontWeight.w600 : FontWeight.normal,
                              color: i == selected ? Colors.white : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
