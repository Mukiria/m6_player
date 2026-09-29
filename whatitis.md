# m6 player: what it is

## The project

**m6 player** is a Flutter music app for Android and iOS, built by Mukiria Six Ventures.

- **Music**: add MP3s from the device and play them as a playlist with next/previous, shuffle, repeat (off / all / one) and a seek bar. Songs are copied into the app's own library folder, so the list survives restarts, and removing a song never touches the original file.
- **Radio**: popular stations for the user's country (from the phone's region setting) via [radio-browser.info](https://www.radio-browser.info), with search.
- **Background playback**: audio keeps playing when the app is in the background, with lock-screen and notification controls.

| | |
|---|---|
| App ID | `com.msixv.com.m6player` (fixed, do not change) |
| Theme | Seeded from brand orange `#F1552C` (fixed, do not change) |
| Repo | https://github.com/Mukiria/m6_player (branch `master`) |
| Platforms | Android, iOS 14.0+ |
| Flutter | 3.44+ required; CI builds on the latest stable (3.47.5 as of 2026-09-29) |

Main code: `lib/screens/` (music and radio screens), `lib/services/` (shared audio player, radio API), `lib/utils/` (file handling, formatting). Unit tests are in `test/`.

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
- The last CI run on `master` passed on Android and iOS (commit `16a461c`).
- A batch of changes is **not committed yet**: radio filtering and error handling, app icons and name, `pubspec.lock`, a README fix, and this file. It hasn't been through CI yet, which happens when it's pushed.
- Nothing has been tested on a real phone yet.

## To do

- [x] **5. Radio error handling**: a failed load now shows "Couldn't load radio stations" with a **Retry** button instead of looking like "no stations". Stations that can't play (HTTP-only) and duplicate streams are hidden. *(done, not yet committed)*
- [x] **6. App icon and name**: `assets/logo.png` is now the Android icon (including the adaptive icon) and all iOS icons, and the home-screen label is "m6 player". *(done, not yet committed)*
- [ ] **7. Widget tests for the two screens**: these need a fake audio player (and a fake `path_provider`) so the screens can be tested without a device.
- [ ] Commit and push the pending batch, then check that CI passes.
- [ ] Test on a real phone: background playback, lock-screen controls, the playlist, adding and removing songs, and the radio.
- [ ] Back up the release keystore and `android/key.properties` (for example in a password manager).
- [ ] Optional: provide a higher-resolution logo (1024 px or larger). The current 300 px logo makes the App Store icon slightly soft.
- [ ] Later: iOS distribution (TestFlight or App Store) needs an Apple Developer account and signing set up.
