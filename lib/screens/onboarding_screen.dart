import 'package:flutter/material.dart';
import '../services/app_settings.dart';
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
    ColorScheme colors = Theme.of(context).colorScheme;
    bool last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: Text(last ? "" : "Skip")),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) {
                  var (icon, title, text) = _pages[index];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: 360),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (index == 0) ...[AppLogo(height: 56), SizedBox(height: 24)],
                            Icon(icon, size: 72, color: colors.primary),
                            SizedBox(height: 24),
                            Text(title,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                            SizedBox(height: 12),
                            Text(text,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, height: 1.4, color: colors.onSurfaceVariant)),
                          ],
                        ),
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
                      color: i == _page ? colors.primary : colors.outlineVariant,
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
    );
  }
}
