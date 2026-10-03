import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../theme.dart';
import '../widgets/m6_icon.dart';
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

  /// The m6 icon's name (see M6Icon) and the label of each tab.
  static const List<(String, String)> _destinations = [
    ('home', 'Home'),
    ('music', 'Music'),
    ('radio', 'Radio'),
    ('videos', 'Video'),
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
                    for (var (icon, label) in _destinations)
                      NavigationRailDestination(icon: M6Icon(icon), label: Text(label)),
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

    // The orange block with rounded top corners: mini player on top (with its progress track), then the nav in a white pill.
    return Scaffold(
      extendBody: true, // The page shows through the nav block's rounded corners
      body: tabs,
      bottomNavigationBar: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        child: Container(
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
      ),
    );
  }
}

/// The floating white bar of tab buttons. Each is just its icon until opened;
/// the open one grows to show its name, on a very transparent black pill.
class _NavPill extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  final List<(String, String)> destinations;

  const _NavPill({required this.selected, required this.onSelected, required this.destinations});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int i = 0; i < destinations.length; i++)
              Semantics(
                button: true,
                selected: i == selected,
                label: destinations[i].$2,
                child: InkWell(
                  key: ValueKey('nav-${destinations[i].$2}'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onSelected(i),
                  // AnimatedSize is the expanding and shrinking; the name just appears with the room
                  child: AnimatedSize(
                    duration: Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 260),
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: i == selected ? Colors.black.withValues(alpha: 0.07) : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          M6Icon(destinations[i].$1, size: 28),
                          if (i == selected) ...[
                            SizedBox(width: 8),
                            Text(
                              destinations[i].$2,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                          ],
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
