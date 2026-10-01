package com.msixv.com.m6player;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import androidx.annotation.NonNull;
import com.ryanheise.audioservice.AudioServiceActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * The app's activity. It extends audio_service's activity (needed for background
 * playback) and adds one call from Flutter: ask for the notification permission,
 * without which Android 13+ may hide the playback controls in the notification panel.
 */
public class MainActivity extends AudioServiceActivity {
    private static final String CHANNEL = "com.msixv.com.m6player/notifications";
    private static final int REQUEST_CODE = 6001;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (!call.method.equals("request")) {
                        result.notImplemented();
                        return;
                    }
                    // Before Android 13 notifications need no permission.
                    if (Build.VERSION.SDK_INT < 33) {
                        result.success(true);
                        return;
                    }
                    boolean granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                            == PackageManager.PERMISSION_GRANTED;
                    if (!granted) {
                        requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, REQUEST_CODE);
                    }
                    result.success(granted);
                });
    }
}
