# m6 player: what it is

## The project

**m6 player** is a Flutter music app for Android and iOS, built by Mukiria Six Ventures.

- **Music**: add MP3s from the device and play them as a playlist with next/previous, shuffle, repeat (off / all / one) and a seek bar. Songs are copied into the app's own library folder, so the list survives restarts, and removing a song never touches the original file.
- **Radio**: popular stations for the user's country (from the phone's region setting) via [radio-browser.info](https://www.radio-browser.info), with search.
- **Background playback**: audio keeps playing when the app is in the background, with lock-screen and notification controls.

| | |
|---|---|
| App ID | `com.msixv.com.m6player` (fixed, do not change) |
| Theme | Brand blue from the logo: accent `#3B82F6` (`#2563EB` on light, `#60A5FA` on dark), navy `#0B1533` for dark mode. Changed from orange `#F1552C` on 2026-10-01 to match the new logo |
| Logos | Source SVGs in `branding/` (from `M6ix/m6 player/`); `node branding/make-icons.js` regenerates `assets/branding/logo-{light,dark}.svg` and all app icons |
| Repo | https://github.com/Mukiria/m6_player (branch `master`) |
| Platforms | Android, iOS 14.0+ |
| Flutter | 3.44+ required; CI builds on the latest stable (3.47.5 as of 2026-09-29) |

Main code: `lib/screens/` (home with the nav bar, music, radio, now playing), `lib/widgets/` (logo, mini player, artwork), `lib/services/` (shared audio player, radio API), `lib/utils/` (file handling, formatting), `lib/theme.dart` (light and dark themes). Unit tests are in `test/`.

**Design**: modelled on Visha Player's layout (Transsion's default player): clean light list screens, a bottom nav bar, a mini player above it, and a dark full-screen Now Playing. Uses m6's own logo and colours, not Visha's branding.

## Where it stands (2026-09-29)

**Done**
- Cleaned up dead code, unused files and packages; dropped the desktop and web targets.
- Upgraded to the latest Flutter toolchain: Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, and current package versions.
- GitHub Actions CI (`.github/workflows/build.yml`) on every push to `master`: analyze, unit tests, release APK (downloadable as the `m6player-apk` artifact) and an unsigned iOS build. Failures show up as annotations on the run.
- Rebuilt playback around one shared player: background audio, a native playlist, and a working Next button.
- Fixed the radio: the old server was dead, and it no longer uses plain-HTTP IP geolocation.
- Safe delete with confirmation; the layout now respects the phone's safe area.
- Release signing via `android/key.properties`. The upload keystore is at `~/keystores/m6player-upload-keystore.jks`. It's gitignored and must never be committed.

**Status**
- Everything is committed and pushed. The latest CI run on `master` (commit `5a775fe`: radio filtering and error handling, app icons and name, `pubspec.lock`) passed on Android and iOS.
- Nothing has been tested on a real phone yet.

## To do

- [x] **5. Radio error handling**: a failed load now shows "Couldn't load radio stations" with a **Retry** button instead of looking like "no stations". Stations that can't play (HTTP-only) and duplicate streams are hidden.
- [x] **6. App icon and name**: `assets/logo.png` is now the Android icon (including the adaptive icon) and all iOS icons, and the home-screen label is "m6 player".
- [x] Commit and push the batch; CI passed (`5a775fe`).
- [ ] **7. Widget tests for the two screens**: these need a fake audio player (and a fake `path_provider`) so the screens can be tested without a device.
- [x] **8. Play next song always works**: Next after the last song now wraps to the first (in shuffle order when shuffle is on); Play after the playlist has finished starts again from the first song; Previous restarts the song if it's more than 3 s in. Songs ending on their own advance through just_audio's playlist (stops after the last song unless repeat is on). Adding and removing songs keep the playlist in step with the list. *Still to check on a real phone.*
- [x] **9. Add folders and multiple items at once**: the + button offers "Choose songs" (several MP3s at once) or "Add a folder" (every MP3 in it and its subfolders). Songs already in the library (same name and size) are skipped. Adding a folder on Android asks for the audio permission (`READ_MEDIA_AUDIO`, or storage on Android 12 and older), through `photo_manager` (`permission_handler` was dropped: its Android part needs compile SDK 37). *Still to check on a real phone, including iOS folder access.*
- [x] **10. Video section**: a Video tab listing every video on the phone (newest first, with thumbnail, length and resolution), via `photo_manager`; nothing is copied. Tapping one opens a full-screen player (`video_player`): tap to show controls, double-tap left/right to skip 10 s, seek bar, previous/next video, rotate button, and the next video plays when one ends. Music pauses when a video starts. Permissions: Android `READ_MEDIA_VIDEO` + `READ_MEDIA_VISUAL_USER_SELECTED` (no photo permission), iOS `NSPhotoLibraryUsageDescription`. The permission prompt appears only when the Video tab is first opened. **Play Console**: the video permission needs the "Photo and video permissions" declaration (core use: video player).
- [ ] **11. Headphone controls**: already provided by the packages: `just_audio_background` routes wired/Bluetooth headset buttons (play/pause, next, previous), and just_audio pauses when headphones are unplugged (`handleInterruptions`, on by default). Needs checking on a real phone only.
- [ ] **12. Notification panel controls**: show m6 player in the phone's notification panel with the song name and play/pause, next and previous buttons. `just_audio_background` should already provide this, but it hasn't been checked on a real phone.
- [x] **13. Navigation bar**: bottom nav bar with Music, Radio and Video.
- [x] **14. New logos and icons (2026-10-01)**: the blue m6 player logo in the app bar (light and dark versions), and new Android (including adaptive) and iOS icons from `m6-player-app-icon-square.svg`. The old orange logo, background photos and fonts were removed.
- [x] **15. Visha-style redesign (2026-10-01)**: Music and Radio tabs as clean lists (the playing item in blue with an equaliser icon, a ⋮ menu with Play and Remove), a mini player above the nav bar, a dark Now Playing screen (seek bar, shuffle, previous, play, next, repeat, and an Up next list), and dark mode following the phone. The volume buttons were dropped (the phone's volume keys do that).
- [ ] Later design ideas: real cover art and artist names from the MP3 tags, sorting, favourites and playlists, a sleep timer.
- [ ] Test on a real phone: background playback, lock-screen controls, the playlist, adding and removing songs, and the radio.
- [ ] Back up the release keystore and `android/key.properties` (for example in a password manager).
- [ ] Later: iOS distribution (TestFlight or App Store) needs an Apple Developer account and signing set up.
