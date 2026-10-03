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
  static const List<(String, String)> _pages = [
    ("Music, videos and radio",
        "Play your songs, watch the videos on your phone and listen to radio stations from around the world, all in one app."),
    ("Add your music",
        "Tap + on the Music tab to add MP3s or a whole folder. Songs are copied into M6 Player, so deleting one here never touches the original."),
    ("Handy touches",
        "Long-press any song or video to select several at once. In the video player, swipe the left side for brightness and the right for volume, double-tap to skip 10 seconds, and hold to play at 2x."),
    ("Permissions",
        "M6 Player may ask to see the videos on your phone. They're only used to play your media. Your music, videos and playlists stay on your phone. The only things that go online are radio: looking up stations and streaming them."),
  ];

  int _page = 0;

  Future<void> _finish() async {
    await AppSettings.instance.setOnboarded();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _step(String title, String text) {
    return Column(
      children: [
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
        SizedBox(height: 4),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.3, color: Colors.white.withValues(alpha: 0.9))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool last = _page == _pages.length - 1;
    // White top with Jacinta, brand-blue panel below with the steps (same in light and dark mode)
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // The animated logo (light version, as it sits on white) stays above every page,
                  // centred on the same line as the Skip button
                  SizedBox(
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AppLogo(height: 56, alwaysAnimate: true, forceLight: true),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _finish,
                            style: TextButton.styleFrom(foregroundColor: brandBlueDark),
                            child: Text(last ? "" : "Skip"),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Jacinta fills the height between the logo and the card, centred, with the page dots over the bottom of her photo
                  Expanded(
                    // Full width, or the Stack shrinks to the page dots and so does Jacinta
                    child: SizedBox(
                      width: double.infinity,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              'assets/brand_ambassador/jacinta-m6-player.jpg',
                              fit: BoxFit.contain, // The photo is tall: it takes the full height, centred
                              alignment: Alignment.center,
                              semanticLabel: "Jacinta, the M6 brand ambassador, dancing with headphones",
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (int i = 0; i < _pages.length; i++)
                                  AnimatedContainer(
                                    duration: Duration(milliseconds: 200),
                                    margin: EdgeInsets.symmetric(horizontal: 3),
                                    width: i == _page ? 20 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: i == _page ? brandBlueDark : brandBlueDark.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: brandOrange,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: SafeArea(
              top: false,
              child: GestureDetector(
                // Swipe left / right between the steps
                onHorizontalDragEnd: (details) {
                  double v = details.primaryVelocity ?? 0;
                  if (v < -200 && _page < _pages.length - 1) setState(() => _page++);
                  if (v > 200 && _page > 0) setState(() => _page--);
                },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // All steps share one spot, so the card is as tall as the longest and doesn't jump.
                      // They sit side by side, one screen width apart, and slide: Next moves them right
                      // to left, going back moves them left to right.
                      ClipRect(
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            for (int i = 0; i < _pages.length; i++)
                              AnimatedSlide(
                                duration: Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                offset: Offset((i - _page).toDouble(), 0),
                                child: ExcludeSemantics(
                                  excluding: i != _page,
                                  child: SizedBox(width: double.infinity, child: _step(_pages[i].$1, _pages[i].$2)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: brandOrange),
                          onPressed: last ? _finish : () => setState(() => _page++),
                          child: Text(last ? "Get started" : "Next"),
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
    );
  }
}
