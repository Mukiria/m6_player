import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m6player/screens/home_screen.dart';
import 'package:m6player/theme.dart';
import 'package:m6player/widgets/app_logo.dart';

/// Screen tests run without a phone, so the audio plugins get fake channels
/// that answer every call with nothing. The music library and radio list then
/// fail to load, which the screens show as their empty and error states.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
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
}
