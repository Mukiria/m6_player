# m6 player

[![Build](https://github.com/Mukiria/m6_player/actions/workflows/build.yml/badge.svg)](https://github.com/Mukiria/m6_player/actions/workflows/build.yml)

A Flutter music app for Android and iOS with two parts:

- **Music**: add MP3s from your device and play them as a playlist with next/previous, shuffle, repeat and a seek bar. Songs are copied into the app's own library, so the list survives restarts, and removing a song never touches the original file.
- **Radio**: popular stations for your country (taken from the phone's region setting) from [radio-browser.info](https://www.radio-browser.info), with search.

Playback continues in the background with lock-screen and notification controls.

## Requirements

- Flutter **3.44 or newer**, on the stable channel (CI always builds with the latest stable)
- Android: JDK 17+
- iOS: iOS 14.0+

## Running

```sh
flutter pub get
flutter run
```

## Tests

```sh
flutter test
```

## Project layout

```
lib/
  main.dart                    app entry; sets up background audio
  screens/
    music_player_screen.dart   library, playlist and player controls
    radio_screen.dart          station list, search and radio playback
  services/
    player_service.dart        the one shared audio player
    radio_api.dart             radio-browser.info client
  utils/
    file_helper.dart           file picking and the music library folder
    format.dart                duration formatting
test/                          unit tests
```

## CI

Every push to `master` runs `.github/workflows/build.yml` on the latest stable Flutter:
analyze, unit tests, a release APK (downloadable as the `m6player-apk` artifact), and an
unsigned iOS build. If a step fails, the error appears as an annotation on the run.

## Release signing (Android)

Release builds are signed with the key described in `android/key.properties`:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Create the keystore by following [Flutter's Android deployment guide](https://docs.flutter.dev/deployment/android#sign-the-app).
`key.properties` and keystore files are gitignored; never commit them. Without `key.properties`,
release builds fall back to the debug key, which is fine for testing but can't be uploaded to the Play Store.

App ID: `com.msixv.com.m6player`
