import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';

/// A few swipeable pages shown once, the first time the app opens: what it
/// does, how to add music, handy gestures, and what the permissions are for.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<(IconData, String, String)> _pages = [
    (Icons.library_music_outlined, "Music, videos and radio",
        "Play your songs, watch the videos on your phone and listen to radio stations from around the world, all in one app."),
    (Icons.add_circle_outline, "Add your music",
        "Tap + on the Music tab to add MP3s or a whole folder. Songs are copied into M6 Player, so deleting one here never touches the original."),
    (Icons.touch_app_outlined, "Handy touches",
        "Long-press any song or video to select several at once. In the video player, swipe the left side for brightness and the right for volume, double-tap to skip 10 seconds, and hold to play at 2x."),
    (Icons.notifications_none, "Permissions",
        "M6 Player may ask to show playback controls in your notifications, and to see the videos on your phone. They're only used to play your media. Your music, videos and playlists stay on your phone. The only things that go online are radio: looking up stations and streaming them."),
  ];

  final PageController _controller = PageController();
  int _page = 0;

  Future<void> _finish() async {
    await AppSettings.instance.setOnboarded();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool last = _page == _pages.length - 1;
    // White top with Jacinta, brand-blue panel below with the steps (same in light and dark mode)
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(foregroundColor: brandBlueDark),
                      child: Text(last ? "" : "Skip"),
                    ),
                  ),
                  // The animated logo (light version, as it sits on white) stays above every page
                  AppLogo(height: 56, alwaysAnimate: true, forceLight: true),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Image.asset(
                        'assets/brand_ambassador/jacinta-m6-player.jpg',
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        semanticLabel: "Jacinta, the M6 brand ambassador, dancing with headphones",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: brandBlueDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 250,
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) {
                        var (icon, title, text) = _pages[index];
                        return Padding(
                          padding: EdgeInsets.fromLTRB(32, 24, 32, 0),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                Icon(icon, size: 36, color: brandOrange),
                                SizedBox(height: 12),
                                Text(title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                                SizedBox(height: 8),
                                Text(text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 15, height: 1.4, color: Colors.white.withValues(alpha: 0.9))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          margin: EdgeInsets.all(4),
                          width: i == _page ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page ? Colors.white : Colors.white38,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: brandBlueDark),
                        onPressed: last
                            ? _finish
                            : () => _controller.nextPage(duration: Duration(milliseconds: 250), curve: Curves.easeOut),
                        child: Text(last ? "Get started" : "Next"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
