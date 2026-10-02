import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/screens/home_screen.dart';
import 'package:m6player/screens/onboarding_screen.dart';
import 'package:m6player/services/app_settings.dart';
import 'package:m6player/services/player_service.dart';
import 'package:m6player/theme.dart';
import 'package:m6player/widgets/app_logo.dart';
import 'package:m6player/widgets/logo_animation_data.dart';
import 'package:m6player/widgets/options_sheet.dart';

/// Screen tests run without a phone, so the audio plugins get fake channels
/// that answer every call with nothing. The music library and radio list then
/// fail to load, which the screens show as their empty and error states.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The first-run intro pages would cover the home screen in every test below
    await AppSettings.instance.setOnboarded();
    for (String channel in [
      'com.ryanheise.just_audio.methods',
      'com.ryanheise.audio_session',
      'com.ryanheise.av_audio_session',
      'com.ryanheise.android_audio_manager',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (call) async => null);
    }
  });

  Widget app({ThemeData? theme}) => MaterialApp(theme: theme ?? lightTheme(), home: const HomeScreen());

  testWidgets('home has Music, Radio and Video tabs, and no mini player before anything plays',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(Duration(milliseconds: 100));

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('No songs yet'), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsNothing); // The mini player is hidden
  });

  testWidgets('the music tab has Songs, Favourites and Playlists, and a sort menu', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(Duration(milliseconds: 100));

    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    expect(find.text('Date added'), findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
    await tester.tapAt(Offset(10, 10)); // Close the menu
    await tester.pumpAndSettle();

    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    expect(find.text('New playlist'), findsOneWidget);
  });

  testWidgets('a wide screen puts the tabs in a side rail; a narrow one keeps the bottom bar', (tester) async {
    await tester.pumpWidget(app()); // The test window is 800 wide
    await tester.pump(Duration(milliseconds: 100));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    tester.view.physicalSize = Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump(Duration(milliseconds: 100));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Radio')); // Switching tabs works from the bottom bar too
    await tester.pump(Duration(milliseconds: 100));
    expect(find.text('Search stations'), findsOneWidget);
  });

  testWidgets('the intro pages step through and close', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: lightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (context) => const OnboardingScreen())),
              child: Text('open intro'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open intro'));
    await tester.pump(); // The tap starts the change; the next frame runs it
    await tester.pump(Duration(milliseconds: 500)); // The animated logo never settles, so no pumpAndSettle

    expect(find.text('Music, videos and radio'), findsOneWidget);
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(Duration(milliseconds: 500)); // The animated logo never settles, so no pumpAndSettle
    }
    expect(find.text('Permissions'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pump(); // Saves the flag, then closes the page
    await tester.pump(); // The page starts to slide away
    await tester.pump(Duration(milliseconds: 500)); // Finished sliding
    expect(find.text('open intro'), findsOneWidget); // Back where we started
  });

  testWidgets('the add button offers songs or a folder', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Add songs'));
    await tester.pumpAndSettle();

    expect(find.text('Choose songs'), findsOneWidget);
    expect(find.text('Add a folder'), findsOneWidget);
  });

  testWidgets('the radio tab offers a retry when stations cannot load', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Radio'));
    // Tests have no network: the station request fails straight away.
    await tester.runAsync(() => Future.delayed(Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Search stations'), findsOneWidget);
  });

  testWidgets('the logo follows the theme', (tester) async {
    String logoAsset() {
      SvgPicture logo = tester.widget(find.descendant(of: find.byType(AppLogo), matching: find.byType(SvgPicture)));
      return (logo.bytesLoader as SvgAssetLoader).assetName;
    }

    await tester.pumpWidget(MaterialApp(theme: lightTheme(), home: Scaffold(body: AppLogo())));
    expect(logoAsset(), 'assets/branding/logo-light.svg');

    await tester.pumpWidget(MaterialApp(theme: darkTheme(), home: Scaffold(body: AppLogo())));
    await tester.pumpAndSettle(); // MaterialApp animates from one theme to the other
    expect(logoAsset(), 'assets/branding/logo-dark.svg');
  });

  testWidgets('the logo animates while something plays and is still otherwise', (tester) async {
    bool isStill() => find.descendant(of: find.byType(AppLogo), matching: find.byType(SvgPicture)).evaluate().any(
        (element) => (element.widget as SvgPicture).bytesLoader is SvgAssetLoader);

    await tester.pumpWidget(MaterialApp(theme: lightTheme(), home: Scaffold(body: AppLogo())));
    expect(isStill(), isTrue);

    PlayerService.instance.videoPlaying.value = true;
    await tester.pump();
    await tester.pump(Duration(seconds: 3)); // Past the intro, into the wave loop
    expect(isStill(), isFalse);
    expect(find.descendant(of: find.byType(AppLogo), matching: find.byType(CustomPaint)), findsWidgets);

    PlayerService.instance.videoPlaying.value = false;
    await tester.pump();
    expect(isStill(), isTrue);
  });

  test('the logo wave data is consistent', () {
    expect(logoViewBox, hasLength(4));
    for (List<double> frame in logoWaveY) {
      expect(frame, hasLength(logoWaveX.length));
    }
    expect(logoWaveY.first, logoWaveY.last); // The loop ends where it starts
  });

  testWidgets('the options sheet shows its title and buttons, and a tap closes it and runs the button', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: lightTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOptionsSheet(context, title: 'Malaika', options: [
              SheetOption(icon: Icons.playlist_play, label: 'Play next', onTap: () => tapped = 'next'),
              SheetOption(icon: Icons.delete_outline, label: 'Delete', destructive: true, onTap: () => tapped = 'delete'),
            ]),
            child: Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Malaika'), findsOneWidget);
    expect(find.byIcon(Icons.playlist_play), findsOneWidget);

    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();
    expect(tapped, 'next');
    expect(find.text('Malaika'), findsNothing); // Closed
  });

  testWidgets('the top-bar menu has light/dark mode and the legal links', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();

    expect(find.text('Light / dark mode'), findsOneWidget);
    expect(find.text('Hidden & filtered'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of service (EULA)'), findsOneWidget);
  });
}
